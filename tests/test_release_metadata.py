from __future__ import annotations

from pathlib import Path

import pytest

from scripts.create_release_metadata import (
    ReleaseMetadataError,
    build_release_metadata,
)
from scripts.verify_curseforge_release import required_game_versions_from_toc


def _write_fixture(root: Path, *, version: str = "1.2.3", interface: str = "120007, 120100") -> Path:
    (root / "ApplicantScout.toc").write_text(
        "\n".join(
            (
                f"## Interface: {interface}",
                "## Title: |cff00ff7fApplicantScout|r: LFG Applicant Overlay",
                f"## Version: {version}",
            )
        )
        + "\n",
        encoding="utf-8",
    )
    release_dir = root / ".release"
    release_dir.mkdir()
    (release_dir / f"ApplicantScout-v{version}.zip").write_bytes(b"zip")
    return release_dir


def test_release_metadata_matches_packager_contract(tmp_path: Path):
    release_dir = _write_fixture(tmp_path)

    assert build_release_metadata(tmp_path, release_dir, "v1.2.3") == {
        "releases": [
            {
                "name": "ApplicantScout: LFG Applicant Overlay",
                "version": "v1.2.3",
                "filename": "ApplicantScout-v1.2.3.zip",
                "nolib": False,
                "metadata": [
                    {"flavor": "mainline", "interface": 120007},
                    {"flavor": "mainline", "interface": 120100},
                ],
            }
        ]
    }


def test_toc_interface_mutation_updates_release_and_marketplace_metadata(
    tmp_path: Path,
):
    release_dir = _write_fixture(tmp_path, interface="130005, 130100")

    metadata = build_release_metadata(tmp_path, release_dir, "v1.2.3")

    assert metadata["releases"][0]["metadata"] == [
        {"flavor": "mainline", "interface": 130005},
        {"flavor": "mainline", "interface": 130100},
    ]
    assert required_game_versions_from_toc(
        tmp_path / "ApplicantScout.toc"
    ) == frozenset({"13.0.5", "13.1.0"})


@pytest.mark.parametrize("tag", ["1.2.3", "v01.2.3", "v1.2.3-beta"])
def test_release_metadata_rejects_noncanonical_tag(tmp_path: Path, tag: str):
    release_dir = _write_fixture(tmp_path)

    with pytest.raises(ReleaseMetadataError, match="exact vMAJOR"):
        build_release_metadata(tmp_path, release_dir, tag)


def test_release_metadata_rejects_tag_version_drift(tmp_path: Path):
    release_dir = _write_fixture(tmp_path)

    with pytest.raises(ReleaseMetadataError, match="does not match TOC"):
        build_release_metadata(tmp_path, release_dir, "v1.2.4")


@pytest.mark.parametrize(
    "interface",
    ["", "0", "11507", "012007", "1200000", "120007, main", "120007, 120007"],
)
def test_release_metadata_rejects_malformed_interfaces(
    tmp_path: Path,
    interface: str,
):
    release_dir = _write_fixture(tmp_path, interface=interface)

    with pytest.raises(ReleaseMetadataError, match="Interface"):
        build_release_metadata(tmp_path, release_dir, "v1.2.3")
