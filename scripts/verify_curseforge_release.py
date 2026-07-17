"""Verify that a CurseForge upload propagated to the public client-facing feed."""

from __future__ import annotations

import argparse
from collections.abc import Callable, Mapping, Sequence
import json
import re
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


PUBLIC_FILES_URL = "https://www.curseforge.com/api/v1/mods/{project_id}/files"
PUBLIC_STATUSES = {4: "Approved", 10: "Released"}
FAILED_STATUSES = {
    2: "ChangesRequired",
    5: "Rejected",
    6: "MalwareDetected",
    7: "Deleted",
    8: "Archived",
    12: "Deprecated",
    15: "FailedPublishing",
}
VERSION_RE = re.compile(r"^v?(\d+\.\d+\.\d+)$")


class MarketplaceVerificationError(RuntimeError):
    """The expected marketplace release is invalid or did not become public."""


def expected_file_name(tag: str) -> str:
    match = VERSION_RE.fullmatch(tag.strip())
    if match is None:
        raise MarketplaceVerificationError(
            f"release tag must be strict vX.Y.Z or X.Y.Z, got {tag!r}"
        )
    return f"ApplicantScout-v{match.group(1)}.zip"


def parse_public_files(payload: object) -> list[Mapping[str, Any]]:
    if isinstance(payload, Mapping):
        payload = payload.get("data", payload.get("items"))
    if not isinstance(payload, list):
        raise MarketplaceVerificationError(
            "CurseForge public files response is not a list"
        )
    files: list[Mapping[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, Mapping):
            raise MarketplaceVerificationError(
                f"CurseForge public files entry {index} is not an object"
            )
        files.append(item)
    return files


def evaluate_public_files(
    files: Sequence[Mapping[str, Any]],
    *,
    project_id: int,
    expected_name: str,
    required_game_versions: frozenset[str],
) -> tuple[bool, str]:
    matching = [item for item in files if item.get("fileName") == expected_name]
    if not matching:
        latest = files[0].get("fileName") if files else "no public files"
        return False, f"{expected_name} is absent; current first file is {latest!r}"
    if len(matching) != 1:
        raise MarketplaceVerificationError(
            f"public feed contains {len(matching)} entries named {expected_name}"
        )

    item = matching[0]
    if item.get("projectId") != project_id:
        raise MarketplaceVerificationError(
            f"{expected_name} belongs to unexpected project {item.get('projectId')!r}"
        )

    status = item.get("status")
    if status in FAILED_STATUSES:
        raise MarketplaceVerificationError(
            f"{expected_name} entered terminal CurseForge status "
            f"{status} ({FAILED_STATUSES[status]})"
        )
    if status not in PUBLIC_STATUSES:
        return False, f"{expected_name} is still in CurseForge status {status!r}"

    versions = item.get("gameVersions")
    if not isinstance(versions, list) or not all(
        isinstance(version, str) for version in versions
    ):
        raise MarketplaceVerificationError(
            f"{expected_name} has malformed gameVersions metadata"
        )
    missing_versions = sorted(required_game_versions - frozenset(versions))
    if missing_versions:
        return False, (
            f"{expected_name} is missing required game versions {missing_versions}; "
            f"published values are {versions}"
        )

    first_name = files[0].get("fileName") if files else None
    if first_name != expected_name:
        return False, (
            f"{expected_name} is public but is not the first client-facing file; "
            f"current first file is {first_name!r}"
        )

    file_id = item.get("id")
    return True, (
        f"{expected_name} is the first public file (id={file_id}, "
        f"status={status} {PUBLIC_STATUSES[status]}, gameVersions={versions})"
    )


def fetch_public_files(
    project_id: int, *, request_timeout: float
) -> list[Mapping[str, Any]]:
    request = Request(
        PUBLIC_FILES_URL.format(project_id=project_id),
        headers={
            "Accept": "application/json",
            "User-Agent": "ApplicantScout-release-verifier/1",
        },
    )
    try:
        with urlopen(request, timeout=request_timeout) as response:  # noqa: S310
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise MarketplaceVerificationError(
            f"could not read CurseForge public files feed: {exc}"
        ) from exc
    return parse_public_files(payload)


def wait_for_public_release(
    *,
    project_id: int,
    expected_name: str,
    required_game_versions: frozenset[str],
    wait_seconds: float,
    poll_seconds: float,
    request_timeout: float,
    fetch: Callable[..., list[Mapping[str, Any]]] = fetch_public_files,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> str:
    deadline = monotonic() + wait_seconds
    last_observation = "verification has not run"
    while True:
        try:
            files = fetch(project_id, request_timeout=request_timeout)
            ready, last_observation = evaluate_public_files(
                files,
                project_id=project_id,
                expected_name=expected_name,
                required_game_versions=required_game_versions,
            )
            if ready:
                return last_observation
        except MarketplaceVerificationError as exc:
            if "terminal CurseForge status" in str(exc):
                raise
            last_observation = str(exc)

        now = monotonic()
        if now >= deadline:
            raise MarketplaceVerificationError(
                "CurseForge public propagation was not verified before the timeout: "
                f"{last_observation}. The upload step has already completed; do not "
                "retry or recreate the upload. Rerun only this read-only verification job."
            )
        sleep(min(poll_seconds, max(0.0, deadline - now)))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tag", required=True, help="Expected addon tag, for example v0.5.3."
    )
    parser.add_argument("--project-id", type=int, required=True)
    parser.add_argument(
        "--game-version",
        action="append",
        default=[],
        help="Required CurseForge game version; repeat for multiple versions.",
    )
    parser.add_argument("--wait-seconds", type=float, default=900.0)
    parser.add_argument("--poll-seconds", type=float, default=15.0)
    parser.add_argument("--request-timeout", type=float, default=20.0)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.project_id <= 0:
        raise MarketplaceVerificationError("project id must be positive")
    if args.wait_seconds < 0 or args.poll_seconds <= 0 or args.request_timeout <= 0:
        raise MarketplaceVerificationError(
            "wait/poll/request timeouts must be positive"
        )
    message = wait_for_public_release(
        project_id=args.project_id,
        expected_name=expected_file_name(args.tag),
        required_game_versions=frozenset(args.game_version),
        wait_seconds=args.wait_seconds,
        poll_seconds=args.poll_seconds,
        request_timeout=args.request_timeout,
    )
    print(f"Verified CurseForge public propagation: {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
