from __future__ import annotations

import shutil
import subprocess
import zipfile
from pathlib import Path

import pytest

from scripts.check_addon_archive import (
    REQUIRED_ENTRIES,
    ArchiveContractError,
    find_marketplace_archive,
    validate_marketplace_archive,
)


def _write_archive(path: Path, *, extra: tuple[str, ...] = (), omit: str = "", changelog: bytes | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        for entry in sorted(str(item) for item in REQUIRED_ENTRIES):
            if entry != omit:
                content = b"fixture"
                if entry == "ApplicantScout/CHANGELOG.md":
                    content = changelog if changelog is not None else (Path(__file__).parents[1] / "CHANGELOG.md").read_bytes()
                archive.writestr(entry, content)
        for entry in extra:
            archive.writestr(entry, b"fixture")


def test_marketplace_archive_accepts_runtime_files_and_changelog(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path)

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


def test_marketplace_archive_rejects_truncated_history(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, changelog=b"# Changelog\n\n## 0.5.3\n\n- Only latest.\n")
    with pytest.raises(ArchiveContractError, match="full changelog history"):
        validate_marketplace_archive(archive_path)


def test_marketplace_archive_rejects_missing_changelog(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, omit="ApplicantScout/CHANGELOG.md")
    with pytest.raises(ArchiveContractError, match="is missing"):
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


def test_manual_package_preserves_full_changelog_bytes(tmp_path: Path):
    powershell = shutil.which("pwsh") or shutil.which("powershell")
    if powershell is None:
        pytest.skip("PowerShell is required for the manual package smoke test")
    root = Path(__file__).resolve().parents[1]
    subprocess.run(
        [
            powershell, "-NoProfile", "-NonInteractive", "-File",
            str(root / "scripts" / "package-addon.ps1"),
            "-AllowDirty", "-OutputDir", str(tmp_path),
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )

    archive_path = find_marketplace_archive(tmp_path)
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.read("ApplicantScout/CHANGELOG.md") == (
            root / "CHANGELOG.md"
        ).read_bytes()
    validate_marketplace_archive(archive_path)


def test_marketplace_archive_rejects_missing_setup_translations(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, omit="ApplicantScout/SetupLocales.lua")
    with pytest.raises(ArchiveContractError, match="SetupLocales.lua"):
        validate_marketplace_archive(archive_path)


def test_marketplace_archive_rejects_missing_setup_example(tmp_path: Path):
    archive_path = tmp_path / "ApplicantScout-0.5.3.zip"
    _write_archive(archive_path, omit="ApplicantScout/media/setup-preview.tga")
    with pytest.raises(ArchiveContractError, match="setup-preview.tga"):
        validate_marketplace_archive(archive_path)


def test_setup_example_is_an_uncompressed_power_of_two_rgba_texture():
    import struct

    texture = (Path(__file__).parents[1] / "media/setup-preview.tga").read_bytes()
    assert texture[1] == 0 and texture[2] == 2, "texture must be uncompressed true-color TGA"
    assert struct.unpack_from("<HH", texture, 12) == (512, 512)
    assert texture[16] == 32 and texture[17] & 0x0F == 8, "RGBA texture must retain its alpha channel"
    assert len(texture) >= 18 + 512 * 512 * 4


@pytest.mark.parametrize("name", ["setup-download", "setup-wcl", "setup-settings"])
def test_setup_illustrations_are_supported_uncompressed_textures(name):
    import struct

    texture = (Path(__file__).parents[1] / "media" / f"{name}.tga").read_bytes()
    assert texture[1] == 0 and texture[2] == 2
    width, height = struct.unpack_from("<HH", texture, 12)
    assert 0 < width <= 1024 and width & (width - 1) == 0
    assert 0 < height <= 1024 and height & (height - 1) == 0
    assert texture[16] in (24, 32)
    assert len(texture) >= 18 + width * height * (texture[16] // 8)
