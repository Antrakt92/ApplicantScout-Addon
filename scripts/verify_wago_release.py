"""Verify that the exact ApplicantScout package is public on Wago Addons."""

from __future__ import annotations

import argparse
from collections.abc import Callable, Mapping
from dataclasses import dataclass
import hashlib
from html.parser import HTMLParser
import io
import json
from pathlib import Path
import re
import stat
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen
import zipfile

if __package__:
    from .create_release_metadata import (
        ReleaseMetadataError,
        _toc_field,
        parse_toc_interfaces,
    )
else:
    from create_release_metadata import (  # type: ignore[no-redef]
        ReleaseMetadataError,
        _toc_field,
        parse_toc_interfaces,
    )


VERSIONS_URL = "https://addons.wago.io/addons/{slug}/versions?stability=stable"
USER_AGENT = "ApplicantScout-release-verifier/1"
MAX_PAGE_BYTES = 4 * 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 128 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 4096
TAG_RE = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
PROJECT_ID_RE = re.compile(r"^[A-Za-z0-9]{8}$")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class MarketplaceVerificationError(RuntimeError):
    """The expected Wago release is invalid or did not become public."""


class TerminalMarketplaceVerificationError(MarketplaceVerificationError):
    """Public state is contradictory and should not be retried as propagation."""


@dataclass(frozen=True)
class ArchiveEntry:
    path: str
    size: int
    sha256: str


@dataclass(frozen=True)
class ArchiveIdentity:
    size: int
    sha256: str
    entries: tuple[ArchiveEntry, ...]


@dataclass(frozen=True)
class PublicRelease:
    release_id: str
    size: int
    download_url: str


class _InertiaPageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.pages: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.casefold() != "div":
            return
        attributes = dict(attrs)
        if attributes.get("id") == "app" and attributes.get("data-page") is not None:
            self.pages.append(attributes["data-page"] or "")


def _strict_tag(tag: str) -> str:
    if TAG_RE.fullmatch(tag) is None:
        raise MarketplaceVerificationError(
            f"release tag must use exact vMAJOR.MINOR.PATCH format, got {tag!r}"
        )
    return tag


def _strict_project_id(project_id: str) -> str:
    if PROJECT_ID_RE.fullmatch(project_id) is None:
        raise MarketplaceVerificationError(
            f"Wago project id must be eight ASCII letters/digits, got {project_id!r}"
        )
    return project_id


def _strict_slug(slug: str) -> str:
    if SLUG_RE.fullmatch(slug) is None:
        raise MarketplaceVerificationError(
            f"Wago addon slug is not canonical, got {slug!r}"
        )
    return slug


def _retail_patch(interface: int) -> str:
    digits = str(interface)
    if len(digits) != 6 or not digits.isascii() or not digits.isdigit():
        raise MarketplaceVerificationError(
            f"mainline TOC Interface must be a six-digit integer, got {interface!r}"
        )
    return ".".join(
        str(int(component)) for component in (digits[:2], digits[2:4], digits[4:6])
    )


def toc_wago_contract(toc_path: Path) -> tuple[str, frozenset[str]]:
    try:
        toc = toc_path.read_text(encoding="utf-8")
        project_id = _strict_project_id(_toc_field(toc, "X-Wago-ID"))
        interfaces = parse_toc_interfaces(toc)
        patches = frozenset(_retail_patch(interface) for interface in interfaces)
    except (OSError, UnicodeError, ReleaseMetadataError) as exc:
        raise MarketplaceVerificationError(
            f"could not derive Wago contract from {toc_path}: {exc}"
        ) from exc
    if len(patches) != len(interfaces):
        raise MarketplaceVerificationError(
            "TOC Interface values collapse to duplicate Wago Retail patches"
        )
    return project_id, patches


def _validated_archive_path(name: str) -> str:
    if (
        not name
        or "\\" in name
        or name.startswith("/")
        or any(ord(character) < 32 for character in name)
    ):
        raise MarketplaceVerificationError(f"unsafe ZIP entry path {name!r}")
    parts = name.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise MarketplaceVerificationError(f"unsafe ZIP entry path {name!r}")
    if ":" in parts[0]:
        raise MarketplaceVerificationError(f"unsafe ZIP entry path {name!r}")
    return "/".join(parts)


def _archive_identity(data: bytes, *, source: str) -> ArchiveIdentity:
    if not data or len(data) > MAX_ARCHIVE_BYTES:
        raise MarketplaceVerificationError(
            f"{source} ZIP size {len(data)} is outside the allowed range"
        )
    raw_hash = hashlib.sha256(data).hexdigest()
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ARCHIVE_ENTRIES:
                raise MarketplaceVerificationError(
                    f"{source} ZIP has too many entries: {len(infos)}"
                )
            seen: set[str] = set()
            seen_casefolded: set[str] = set()
            total_size = 0
            entries: list[ArchiveEntry] = []
            for info in infos:
                raw_name = info.filename.rstrip("/") if info.is_dir() else info.filename
                path = _validated_archive_path(raw_name)
                folded = path.casefold()
                if path in seen or folded in seen_casefolded:
                    raise MarketplaceVerificationError(
                        f"{source} ZIP has a duplicate path: {path}"
                    )
                seen.add(path)
                seen_casefolded.add(folded)
                if info.create_system == 3 and stat.S_ISLNK(info.external_attr >> 16):
                    raise MarketplaceVerificationError(
                        f"{source} ZIP contains a symbolic link: {path}"
                    )
                if info.flag_bits & 0x1:
                    raise MarketplaceVerificationError(
                        f"{source} ZIP contains an encrypted entry: {path}"
                    )
                if info.is_dir():
                    continue
                total_size += info.file_size
                if total_size > MAX_UNCOMPRESSED_BYTES:
                    raise MarketplaceVerificationError(
                        f"{source} ZIP exceeds the uncompressed-size budget"
                    )
                if info.file_size > max(1024 * 1024, info.compress_size * 1000):
                    raise MarketplaceVerificationError(
                        f"{source} ZIP entry has an unsafe compression ratio: {path}"
                    )
                with archive.open(info) as member:
                    payload = member.read(info.file_size + 1)
                if len(payload) != info.file_size:
                    raise MarketplaceVerificationError(
                        f"{source} ZIP entry size is inconsistent: {path}"
                    )
                entries.append(
                    ArchiveEntry(
                        path, info.file_size, hashlib.sha256(payload).hexdigest()
                    )
                )
    except (zipfile.BadZipFile, NotImplementedError, RuntimeError, OSError) as exc:
        raise MarketplaceVerificationError(
            f"{source} is not a safe readable ZIP: {exc}"
        ) from exc
    if not entries:
        raise MarketplaceVerificationError(f"{source} ZIP contains no files")
    return ArchiveIdentity(
        len(data), raw_hash, tuple(sorted(entries, key=lambda item: item.path))
    )


def archive_identity_from_path(archive_path: Path, *, tag: str) -> ArchiveIdentity:
    tag = _strict_tag(tag)
    expected_name = f"ApplicantScout-{tag}.zip"
    if archive_path.name != expected_name:
        raise MarketplaceVerificationError(
            f"expected verified exact-tag archive {expected_name}, got {archive_path.name!r}"
        )
    try:
        data = archive_path.read_bytes()
    except OSError as exc:
        raise MarketplaceVerificationError(
            f"could not read expected verified exact-tag archive {archive_path}: {exc}"
        ) from exc
    return _archive_identity(data, source="expected verified exact-tag archive")


def parse_public_page(document: str) -> Mapping[str, Any]:
    parser = _InertiaPageParser()
    parser.feed(document)
    parser.close()
    if len(parser.pages) != 1:
        raise MarketplaceVerificationError(
            f"Wago versions page contains {len(parser.pages)} Inertia app payloads"
        )
    try:
        page = json.loads(parser.pages[0])
    except json.JSONDecodeError as exc:
        raise MarketplaceVerificationError(
            f"Wago versions page has malformed Inertia JSON: {exc}"
        ) from exc
    if not isinstance(page, Mapping):
        raise MarketplaceVerificationError("Wago Inertia payload is not an object")
    return page


def _mapping(value: object, *, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise MarketplaceVerificationError(f"Wago {field} is not an object")
    return value


def _validate_download_url(
    url: str,
    *,
    project_id: str,
    tag: str,
    final: bool,
    release_id: str | None = None,
) -> None:
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as exc:
        raise TerminalMarketplaceVerificationError(
            f"Wago download URL is malformed: {url!r}"
        ) from exc
    if (
        parsed.scheme != "https"
        or parsed.username is not None
        or parsed.password is not None
        or port not in {None, 443}
        or parsed.fragment
    ):
        raise TerminalMarketplaceVerificationError(
            f"Wago download URL is not an allowed credentialless HTTPS URL: {url!r}"
        )
    host = (parsed.hostname or "").casefold()
    decoded_path = unquote(parsed.path)
    if not final:
        valid = (
            release_id is not None
            and host == "addons.wago.io"
            and decoded_path == f"/download/{release_id}"
        )
    elif host == "addons.wago.io":
        valid = decoded_path.startswith("/download/")
    else:
        expected_suffix = f"/ApplicantScout-{tag}.zip"
        valid = (
            host == "cdn.wago.io"
            and decoded_path.startswith(f"/public/addons/{project_id}/")
            and decoded_path.endswith(expected_suffix)
        )
    if not valid:
        raise TerminalMarketplaceVerificationError(
            f"Wago download URL escaped the allowed project path: {url!r}"
        )


def evaluate_public_page(
    page: Mapping[str, Any],
    *,
    project_id: str,
    slug: str,
    tag: str,
    required_patches: frozenset[str],
) -> tuple[bool, str, PublicRelease | None]:
    if page.get("component") != "Addon/Releases":
        raise MarketplaceVerificationError(
            f"unexpected Wago Inertia component {page.get('component')!r}"
        )
    props = _mapping(page.get("props"), field="props")
    addon = _mapping(props.get("addon"), field="addon metadata")
    if addon.get("id") != project_id or addon.get("slug") != slug:
        raise TerminalMarketplaceVerificationError(
            "Wago versions page belongs to an unexpected addon identity"
        )
    if props.get("stability") != "stable":
        raise MarketplaceVerificationError(
            "Wago versions page is not filtered to stable"
        )
    releases = _mapping(props.get("releases"), field="releases collection")
    if releases.get("current_page") != 1:
        raise MarketplaceVerificationError(
            "Wago releases payload is not the first page"
        )
    data = releases.get("data")
    if not isinstance(data, list) or not all(
        isinstance(item, Mapping) for item in data
    ):
        raise MarketplaceVerificationError(
            "Wago releases data is not a list of objects"
        )
    matching = [item for item in data if item.get("label") == tag]
    if not matching:
        latest = data[0].get("label") if data else "no public releases"
        return (
            False,
            f"{tag} is absent; current first stable release is {latest!r}",
            None,
        )
    if len(matching) != 1:
        raise TerminalMarketplaceVerificationError(
            f"Wago public page contains {len(matching)} releases labelled {tag}"
        )
    item = matching[0]
    if not data or data[0].get("label") != tag:
        return (
            False,
            (
                f"{tag} is public but is not the first stable release; "
                f"current first release is {data[0].get('label')!r}"
            ),
            None,
        )
    addon_id = item.get("addon_id")
    if isinstance(addon_id, bool) or not isinstance(addon_id, int) or addon_id <= 0:
        raise MarketplaceVerificationError(f"{tag} has malformed internal addon_id")
    if item.get("stability") != "stable":
        raise TerminalMarketplaceVerificationError(
            f"{tag} is not a stable Wago release"
        )
    processed = item.get("is_processed")
    if not isinstance(processed, bool):
        raise MarketplaceVerificationError(f"{tag} has malformed is_processed metadata")
    if not processed:
        return False, f"{tag} is not processed yet", None
    excluded = item.get("is_excluded_from_matching")
    if not isinstance(excluded, bool):
        raise MarketplaceVerificationError(
            f"{tag} has malformed is_excluded_from_matching metadata"
        )
    if excluded:
        raise TerminalMarketplaceVerificationError(
            f"{tag} is excluded from Wago client matching"
        )
    patches = item.get("supported_retail_patches")
    if not isinstance(patches, list) or not all(
        isinstance(patch, str) for patch in patches
    ):
        raise MarketplaceVerificationError(f"{tag} has malformed Retail patch metadata")
    if len(patches) != len(set(patches)):
        raise MarketplaceVerificationError(f"{tag} has duplicate Retail patch metadata")
    if frozenset(patches) != required_patches:
        return (
            False,
            (
                f"{tag} Retail patches {patches} do not match exact-tag TOC patches "
                f"{sorted(required_patches)}"
            ),
            None,
        )
    size = item.get("size")
    if (
        isinstance(size, bool)
        or not isinstance(size, int)
        or size <= 0
        or size > MAX_ARCHIVE_BYTES
    ):
        raise MarketplaceVerificationError(f"{tag} has malformed archive size {size!r}")
    release_id = item.get("id")
    download_url = item.get("download_link")
    if not isinstance(release_id, str) or not release_id:
        raise MarketplaceVerificationError(f"{tag} has malformed release id")
    if not isinstance(download_url, str) or not download_url:
        raise MarketplaceVerificationError(f"{tag} has no public download link")
    _validate_download_url(
        download_url,
        project_id=project_id,
        tag=tag,
        final=False,
        release_id=release_id,
    )
    return (
        True,
        f"{tag} is the first processed stable Wago release",
        PublicRelease(
            release_id=release_id,
            size=size,
            download_url=download_url,
        ),
    )


def _read_bounded(response: Any, *, limit: int, source: str) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = response.read(min(64 * 1024, limit + 1 - total))
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > limit:
            raise MarketplaceVerificationError(f"{source} exceeded {limit} bytes")
    return b"".join(chunks)


def fetch_public_page(slug: str, *, request_timeout: float) -> Mapping[str, Any]:
    request = Request(
        VERSIONS_URL.format(slug=slug),
        headers={"Accept": "text/html", "User-Agent": USER_AGENT},
    )
    try:
        with urlopen(request, timeout=request_timeout) as response:  # noqa: S310
            document = _read_bounded(
                response, limit=MAX_PAGE_BYTES, source="Wago versions page"
            ).decode("utf-8")
    except (HTTPError, URLError, TimeoutError, UnicodeError, OSError) as exc:
        raise MarketplaceVerificationError(
            f"could not read Wago public versions page: {exc}"
        ) from exc
    return parse_public_page(document)


def fetch_public_archive(
    download_url: str,
    *,
    project_id: str,
    tag: str,
    release_id: str,
    expected_size: int,
    request_timeout: float,
) -> bytes:
    _validate_download_url(
        download_url,
        project_id=project_id,
        tag=tag,
        final=False,
        release_id=release_id,
    )
    request = Request(
        download_url,
        headers={"Accept": "application/zip", "User-Agent": USER_AGENT},
    )
    try:
        with urlopen(request, timeout=request_timeout) as response:  # noqa: S310
            final_url = response.geturl()
            _validate_download_url(
                final_url, project_id=project_id, tag=tag, final=True
            )
            content_length = response.headers.get("Content-Length")
            if content_length is not None:
                try:
                    header_size = int(content_length)
                except ValueError as exc:
                    raise MarketplaceVerificationError(
                        "Wago download has malformed Content-Length"
                    ) from exc
                if header_size != expected_size:
                    raise MarketplaceVerificationError(
                        f"Wago download Content-Length {header_size} does not match "
                        f"public metadata size {expected_size}"
                    )
            data = _read_bounded(
                response, limit=expected_size, source="Wago public archive"
            )
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise MarketplaceVerificationError(
            f"could not download Wago public archive: {exc}"
        ) from exc
    if len(data) != expected_size:
        raise MarketplaceVerificationError(
            f"Wago public archive size {len(data)} does not match metadata {expected_size}"
        )
    return data


def wait_for_public_release(
    *,
    project_id: str,
    slug: str,
    tag: str,
    required_patches: frozenset[str],
    expected_archive: ArchiveIdentity,
    wait_seconds: float,
    poll_seconds: float,
    request_timeout: float,
    fetch_page: Callable[..., Mapping[str, Any]] = fetch_public_page,
    fetch_archive: Callable[..., bytes] = fetch_public_archive,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> str:
    deadline = monotonic() + wait_seconds
    last_observation = "verification has not run"
    while True:
        try:
            page = fetch_page(slug, request_timeout=request_timeout)
            ready, last_observation, release = evaluate_public_page(
                page,
                project_id=project_id,
                slug=slug,
                tag=tag,
                required_patches=required_patches,
            )
            if ready and release is not None:
                data = fetch_archive(
                    release.download_url,
                    project_id=project_id,
                    tag=tag,
                    release_id=release.release_id,
                    expected_size=release.size,
                    request_timeout=request_timeout,
                )
                public_archive = _archive_identity(data, source="Wago public archive")
                if public_archive.entries == expected_archive.entries:
                    return (
                        f"{last_observation}; public archive {release.release_id} "
                        f"matches all {len(public_archive.entries)} packaged file payloads "
                        f"(size={public_archive.size}, sha256={public_archive.sha256})"
                    )
                last_observation = (
                    f"{tag} public ZIP contents do not match the verified exact-tag "
                    "package"
                )
        except TerminalMarketplaceVerificationError:
            raise
        except MarketplaceVerificationError as exc:
            last_observation = str(exc)

        now = monotonic()
        if now >= deadline:
            raise MarketplaceVerificationError(
                "Wago public propagation was not verified before the timeout: "
                f"{last_observation}. The upload step has already completed and may "
                "have succeeded; do not retry or recreate the upload. Rerun only this "
                "read-only verification job."
            )
        sleep(min(poll_seconds, max(0.0, deadline - now)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--addon-slug", required=True)
    parser.add_argument("--toc", type=Path, default=Path("ApplicantScout.toc"))
    parser.add_argument("--expected-archive", type=Path, required=True)
    parser.add_argument("--wait-seconds", type=float, default=900.0)
    parser.add_argument("--poll-seconds", type=float, default=15.0)
    parser.add_argument("--request-timeout", type=float, default=20.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    tag = _strict_tag(args.tag)
    project_id = _strict_project_id(args.project_id)
    slug = _strict_slug(args.addon_slug)
    toc_project_id, patches = toc_wago_contract(args.toc)
    if toc_project_id != project_id:
        raise MarketplaceVerificationError(
            f"workflow Wago project {project_id} does not match TOC {toc_project_id}"
        )
    if args.wait_seconds < 0 or args.poll_seconds <= 0 or args.request_timeout <= 0:
        raise MarketplaceVerificationError(
            "wait must be non-negative and poll/request timeouts must be positive"
        )
    expected_archive = archive_identity_from_path(args.expected_archive, tag=tag)
    message = wait_for_public_release(
        project_id=project_id,
        slug=slug,
        tag=tag,
        required_patches=patches,
        expected_archive=expected_archive,
        wait_seconds=args.wait_seconds,
        poll_seconds=args.poll_seconds,
        request_timeout=args.request_timeout,
    )
    print(f"Verified Wago public propagation: {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
