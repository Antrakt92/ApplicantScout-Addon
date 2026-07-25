from __future__ import annotations

from html import escape
import io
import json
from pathlib import Path
from typing import Any
import zipfile

import pytest

from scripts.verify_wago_release import (
    MarketplaceVerificationError,
    TerminalMarketplaceVerificationError,
    _archive_identity,
    _validated_archive_path,
    _validate_download_url,
    archive_identity_from_path,
    evaluate_public_page,
    parse_public_page,
    toc_wago_contract,
    wait_for_public_release,
)


PROJECT_ID = "ANzke264"
SLUG = "applicantscout-addon"
TAG = "v0.8.1"
PATCHES = frozenset({"12.0.7", "12.1.0"})
DOWNLOAD_URL = "https://addons.wago.io/download/ld3Wjqyd?signature=test"


def _zip_bytes(
    files: dict[str, bytes] | None = None,
    *,
    timestamp: tuple[int, int, int, int, int, int] = (2026, 7, 25, 12, 0, 0),
) -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, payload in (
            files or {"ApplicantScout/ApplicantScout.lua": b"ok"}
        ).items():
            info = zipfile.ZipInfo(name, timestamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload)
    return stream.getvalue()


def _release(**overrides: object) -> dict[str, object]:
    release: dict[str, object] = {
        "id": "ld3Wjqyd",
        "addon_id": 4941,
        "size": len(_zip_bytes()),
        "label": TAG,
        "stability": "stable",
        "is_processed": True,
        "is_excluded_from_matching": False,
        "supported_retail_patches": ["12.0.7", "12.1.0"],
        "download_link": DOWNLOAD_URL,
    }
    release.update(overrides)
    return release


def _page(*releases: dict[str, object], **addon_overrides: object) -> dict[str, Any]:
    addon: dict[str, object] = {"id": PROJECT_ID, "slug": SLUG}
    addon.update(addon_overrides)
    return {
        "component": "Addon/Releases",
        "props": {
            "stability": "stable",
            "addon": addon,
            "releases": {"current_page": 1, "data": list(releases or (_release(),))},
        },
    }


def _evaluate(page: dict[str, Any]):
    return evaluate_public_page(
        page,
        project_id=PROJECT_ID,
        slug=SLUG,
        tag=TAG,
        required_patches=PATCHES,
    )


def test_toc_contract_derives_project_and_exact_retail_patches(tmp_path: Path):
    toc = tmp_path / "ApplicantScout.toc"
    toc.write_text(
        "## Interface: 120007, 120100\n## X-Wago-ID: ANzke264\n",
        encoding="utf-8",
    )

    assert toc_wago_contract(toc) == (PROJECT_ID, PATCHES)

    toc.write_text("## Interface: 120007\n## X-Wago-ID: wrong-id\n", encoding="utf-8")
    with pytest.raises(MarketplaceVerificationError, match="project id"):
        toc_wago_contract(toc)


def test_archive_identity_ignores_zip_timestamps_but_not_file_payloads():
    first = _archive_identity(
        _zip_bytes(timestamp=(2026, 7, 25, 12, 0, 0)), source="first"
    )
    rebuilt = _archive_identity(
        _zip_bytes(timestamp=(2026, 7, 25, 12, 10, 0)), source="rebuilt"
    )
    changed = _archive_identity(
        _zip_bytes({"ApplicantScout/ApplicantScout.lua": b"changed"}),
        source="changed",
    )

    assert first.sha256 != rebuilt.sha256
    assert first.entries == rebuilt.entries
    assert first.entries != changed.entries


@pytest.mark.parametrize(
    "name",
    (
        "../ApplicantScout.lua",
        "/ApplicantScout/ApplicantScout.lua",
        "C:/ApplicantScout/ApplicantScout.lua",
    ),
)
def test_archive_identity_rejects_unsafe_paths(name: str):
    with pytest.raises(MarketplaceVerificationError, match="unsafe ZIP entry"):
        _archive_identity(_zip_bytes({name: b"bad"}), source="public")


def test_archive_path_rejects_windows_separators_before_normalization():
    with pytest.raises(MarketplaceVerificationError, match="unsafe ZIP entry"):
        _validated_archive_path("ApplicantScout\\ApplicantScout.lua")

    with pytest.raises(MarketplaceVerificationError, match="unsafe ZIP entry"):
        _validated_archive_path("ApplicantScout/control\x00.lua")


def test_expected_archive_requires_exact_tag_filename(tmp_path: Path):
    archive = tmp_path / "ApplicantScout-v0.8.0.zip"
    archive.write_bytes(_zip_bytes())

    with pytest.raises(
        MarketplaceVerificationError, match="verified exact-tag archive"
    ):
        archive_identity_from_path(archive, tag=TAG)

    with pytest.raises(MarketplaceVerificationError, match="exact vMAJOR"):
        archive_identity_from_path(archive, tag="0.8.1")


def test_parse_public_page_extracts_one_inertia_payload():
    page = _page()
    document = f'<html><div id="app" data-page="{escape(json.dumps(page), quote=True)}"></div></html>'

    assert parse_public_page(document) == page

    with pytest.raises(MarketplaceVerificationError, match="0 Inertia"):
        parse_public_page("<html></html>")


def test_public_release_requires_exact_identity_and_processed_stable_metadata():
    ready, message, release = _evaluate(_page())

    assert ready is True
    assert "first processed stable" in message
    assert release is not None
    assert release.download_url == DOWNLOAD_URL

    with pytest.raises(TerminalMarketplaceVerificationError, match="identity"):
        _evaluate(_page(**{"id": "ABCDEFGH"}))

    with pytest.raises(TerminalMarketplaceVerificationError, match="not a stable"):
        _evaluate(_page(_release(stability="beta")))

    page = _page()
    page["props"]["releases"]["current_page"] = 2
    with pytest.raises(MarketplaceVerificationError, match="first page"):
        _evaluate(page)


def test_public_release_waits_for_absent_stale_processing_and_patch_states():
    ready, message, release = _evaluate(_page(_release(label="v0.8.0")))
    assert (ready, release) == (False, None)
    assert "absent" in message

    ready, message, release = _evaluate(_page(_release(label="v0.8.2"), _release()))
    assert (ready, release) == (False, None)
    assert "not the first" in message

    ready, message, release = _evaluate(_page(_release(is_processed=False)))
    assert (ready, release) == (False, None)
    assert "not processed" in message

    ready, message, release = _evaluate(
        _page(_release(supported_retail_patches=["12.0.7"]))
    )
    assert (ready, release) == (False, None)
    assert "do not match" in message


def test_public_release_rejects_duplicate_tag_and_excluded_release():
    with pytest.raises(TerminalMarketplaceVerificationError, match="2 releases"):
        _evaluate(_page(_release(), _release(id="another")))

    with pytest.raises(TerminalMarketplaceVerificationError, match="excluded"):
        _evaluate(_page(_release(is_excluded_from_matching=True)))


@pytest.mark.parametrize(
    "url",
    (
        "http://addons.wago.io/download/ld3Wjqyd",
        "https://user@addons.wago.io/download/ld3Wjqyd",
        "https://example.com/download/ld3Wjqyd",
        "https://addons.wago.io/not-download/ld3Wjqyd",
        "https://addons.wago.io:invalid/download/ld3Wjqyd",
    ),
)
def test_download_url_rejects_non_wago_or_non_download_paths(url: str):
    with pytest.raises(TerminalMarketplaceVerificationError):
        _validate_download_url(
            url,
            project_id=PROJECT_ID,
            tag=TAG,
            final=False,
            release_id="ld3Wjqyd",
        )


def test_final_download_url_is_bound_to_project_and_archive_name():
    _validate_download_url(
        f"https://cdn.wago.io/public/addons/{PROJECT_ID}/token/ApplicantScout-{TAG}.zip",
        project_id=PROJECT_ID,
        tag=TAG,
        final=True,
    )

    with pytest.raises(TerminalMarketplaceVerificationError, match="project path"):
        _validate_download_url(
            f"https://cdn.wago.io/public/addons/ABCDEFGH/token/ApplicantScout-{TAG}.zip",
            project_id=PROJECT_ID,
            tag=TAG,
            final=True,
        )


def test_waiter_recovers_then_matches_every_packaged_file_payload():
    expected_data = _zip_bytes(timestamp=(2026, 7, 25, 12, 0, 0))
    public_data = _zip_bytes(timestamp=(2026, 7, 25, 12, 10, 0))
    expected = _archive_identity(expected_data, source="expected")
    pages = [
        _page(_release(label="v0.8.0")),
        _page(_release(is_processed=False)),
        _page(_release(size=len(public_data))),
    ]
    clock = iter((0.0, 0.0, 1.0))

    def fetch_page(slug: str, *, request_timeout: float):
        assert slug == SLUG
        assert request_timeout == 20.0
        return pages.pop(0)

    def fetch_archive(
        url: str,
        *,
        project_id: str,
        tag: str,
        release_id: str,
        expected_size: int,
        request_timeout: float,
    ) -> bytes:
        assert (url, project_id, tag) == (DOWNLOAD_URL, PROJECT_ID, TAG)
        assert release_id == "ld3Wjqyd"
        assert expected_size == len(public_data)
        assert request_timeout == 20.0
        return public_data

    message = wait_for_public_release(
        project_id=PROJECT_ID,
        slug=SLUG,
        tag=TAG,
        required_patches=PATCHES,
        expected_archive=expected,
        wait_seconds=10.0,
        poll_seconds=1.0,
        request_timeout=20.0,
        fetch_page=fetch_page,
        fetch_archive=fetch_archive,
        monotonic=lambda: next(clock),
        sleep=lambda _seconds: None,
    )

    assert "matches all 1 packaged file payloads" in message
    assert pages == []


def test_waiter_content_mismatch_times_out_with_verify_only_recovery():
    expected = _archive_identity(_zip_bytes(), source="expected")
    changed = _zip_bytes({"ApplicantScout/ApplicantScout.lua": b"changed"})
    page = _page(_release(size=len(changed)))
    clock = iter((0.0, 0.0))

    with pytest.raises(
        MarketplaceVerificationError, match="Rerun only this read-only verification"
    ):
        wait_for_public_release(
            project_id=PROJECT_ID,
            slug=SLUG,
            tag=TAG,
            required_patches=PATCHES,
            expected_archive=expected,
            wait_seconds=0.0,
            poll_seconds=1.0,
            request_timeout=20.0,
            fetch_page=lambda _slug, request_timeout: page,
            fetch_archive=lambda _url, **_kwargs: changed,
            monotonic=lambda: next(clock),
            sleep=lambda _seconds: None,
        )
