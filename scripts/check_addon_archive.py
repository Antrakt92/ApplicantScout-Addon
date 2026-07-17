"""Validate the archive emitted by the marketplace packager dry run."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import zipfile


ADDON_NAME = "ApplicantScout"
REQUIRED_ENTRIES = frozenset(
    {
        PurePosixPath(f"{ADDON_NAME}/ApplicantScout.toc"),
        PurePosixPath(f"{ADDON_NAME}/ApplicantScout.lua"),
        PurePosixPath(f"{ADDON_NAME}/LICENSE"),
        PurePosixPath(f"{ADDON_NAME}/THIRD-PARTY-NOTICES.md"),
        PurePosixPath(f"{ADDON_NAME}/media/logo.png"),
        PurePosixPath(f"{ADDON_NAME}/libs/qrencode.lua"),
    }
)
FORBIDDEN_NAMES = frozenset(
    {
        ".gitignore",
        ".pkgmeta",
        "agents.md",
        "audit.md",
        "claude.md",
        "notes.md",
        "plan.md",
        "readme.md",
        "todo.md",
    }
)
FORBIDDEN_PARTS = frozenset(
    {".git", ".github", "docs", "scripts", "tests", "savedvariables"}
)


class ArchiveContractError(ValueError):
    """The generated addon archive does not match the public package contract."""


def find_marketplace_archive(release_dir: Path) -> Path:
    archives = sorted(release_dir.glob(f"{ADDON_NAME}-*.zip"))
    if len(archives) != 1:
        raise ArchiveContractError(
            f"expected exactly one marketplace archive, found {archives}"
        )
    return archives[0]


def _archive_entries(archive_path: Path) -> set[PurePosixPath]:
    if not archive_path.is_file():
        raise ArchiveContractError(f"marketplace archive does not exist: {archive_path}")
    try:
        with zipfile.ZipFile(archive_path) as archive:
            return {
                PurePosixPath(name.replace("\\", "/"))
                for name in archive.namelist()
                if not name.endswith(("/", "\\"))
            }
    except zipfile.BadZipFile as exc:
        raise ArchiveContractError(
            f"marketplace archive is not a readable ZIP: {archive_path}"
        ) from exc


def _is_forbidden(entry: PurePosixPath) -> bool:
    parts = entry.parts
    if not parts or parts[0] != ADDON_NAME:
        return True
    child_parts = tuple(part.casefold() for part in parts[1:])
    if any(part in FORBIDDEN_PARTS for part in child_parts):
        return True
    name = entry.name.casefold()
    if name in FORBIDDEN_NAMES or name.endswith(".private.md"):
        return True
    return any(part.endswith(".private") for part in child_parts[:-1])


def validate_marketplace_archive(archive_path: Path) -> None:
    entries = _archive_entries(archive_path)
    missing = sorted(str(path) for path in REQUIRED_ENTRIES - entries)
    if missing:
        raise ArchiveContractError(f"marketplace archive is missing: {missing}")
    forbidden = sorted(str(entry) for entry in entries if _is_forbidden(entry))
    if forbidden:
        raise ArchiveContractError(
            f"marketplace archive contains forbidden paths: {forbidden}"
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--release-dir",
        type=Path,
        required=True,
        help="Directory containing exactly one ApplicantScout marketplace ZIP.",
    )
    return parser.parse_args()


def main() -> int:
    archive_path = find_marketplace_archive(parse_args().release_dir)
    validate_marketplace_archive(archive_path)
    print(f"Validated marketplace archive: {archive_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
