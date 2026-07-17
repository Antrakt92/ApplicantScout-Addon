from __future__ import annotations

from pathlib import Path
import zipfile

import pytest

from scripts.check_addon_archive import (
    ArchiveContractError,
    REQUIRED_ENTRIES,
    find_marketplace_archive,
    validate_marketplace_archive,
)


def _write_archive(path: Path, *, extra: tuple[str, ...] = (), omit: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        for entry in sorted(str(item) for item in REQUIRED_ENTRIES):
            if entry != omit:
                archive.writestr(entry, b"fixture")
        for entry in extra:
            archive.writestr(entry, b"fixture")


def test_marketplace_archive_accepts_runtime_files_and_changelog(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, extra=("ApplicantScout/CHANGELOG.md",))

    validate_marketplace_archive(archive_path)


@pytest.mark.parametrize(
    "forbidden",
    (
        "repo-wrapper/ApplicantScout/ApplicantScout.lua",
        "ApplicantScout/.pkgmeta",
        "ApplicantScout/.github/workflows/release.yml",
        "ApplicantScout/docs/private.png",
        "ApplicantScout/scripts/release.ps1",
        "ApplicantScout/tests/test_runtime.py",
        "ApplicantScout/AGENTS.md",
        "ApplicantScout/secret.private.md",
        "ApplicantScout/config.private/token.txt",
        "ApplicantScout/SavedVariables/ApplicantScout.lua",
    ),
)
def test_marketplace_archive_rejects_dev_and_private_paths(
    tmp_path: Path, forbidden: str
):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, extra=(forbidden,))

    with pytest.raises(ArchiveContractError, match="forbidden paths"):
        validate_marketplace_archive(archive_path)


def test_marketplace_archive_rejects_missing_runtime_file(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, omit="ApplicantScout/libs/qrencode.lua")

    with pytest.raises(ArchiveContractError, match="is missing"):
        validate_marketplace_archive(archive_path)


def test_marketplace_archive_rejects_malformed_zip(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    archive_path.write_bytes(b"not a zip")

    with pytest.raises(ArchiveContractError, match="not a readable ZIP"):
        validate_marketplace_archive(archive_path)


def test_find_marketplace_archive_requires_exactly_one_zip(tmp_path: Path):
    with pytest.raises(ArchiveContractError, match="exactly one"):
        find_marketplace_archive(tmp_path)

    _write_archive(tmp_path / "ApplicantScout-one.zip")
    assert find_marketplace_archive(tmp_path).name == "ApplicantScout-one.zip"

    _write_archive(tmp_path / "ApplicantScout-two.zip")
    with pytest.raises(ArchiveContractError, match="exactly one"):
        find_marketplace_archive(tmp_path)
