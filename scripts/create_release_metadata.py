"""Create the GitHub release.json for an exact ApplicantScout tag archive."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


ADDON_NAME = "ApplicantScout"
_SEMVER_TAG = re.compile(r"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class ReleaseMetadataError(ValueError):
    """The exact-tag package metadata is incomplete or inconsistent."""


def _toc_field(toc: str, field: str) -> str:
    matches = re.findall(rf"(?m)^##\s*{re.escape(field)}:\s*(.+?)\s*$", toc)
    if len(matches) != 1:
        raise ReleaseMetadataError(f"TOC must contain exactly one {field} field")
    return matches[0]


def _display_title(raw_title: str) -> str:
    title = re.sub(r"\|c[0-9A-Fa-f]{8}", "", raw_title).replace("|r", "")
    if not title.strip():
        raise ReleaseMetadataError("TOC Title becomes empty after WoW colour removal")
    return title.strip()


def parse_toc_interfaces(toc: str) -> tuple[int, ...]:
    interface_text = _toc_field(toc, "Interface")
    interface_parts = [part.strip() for part in interface_text.split(",")]
    if not interface_parts or any(
        len(part) != 6
        or part.startswith("0")
        or not part.isascii()
        or not part.isdigit()
        for part in interface_parts
    ):
        raise ReleaseMetadataError(
            "TOC Interface must contain comma-separated six-digit ASCII "
            "mainline integers"
        )
    interfaces = tuple(int(part) for part in interface_parts)
    if len(interfaces) != len(set(interfaces)):
        raise ReleaseMetadataError("TOC Interface contains duplicate values")
    return interfaces


def build_release_metadata(root: Path, release_dir: Path, tag: str) -> dict[str, object]:
    if not _SEMVER_TAG.fullmatch(tag):
        raise ReleaseMetadataError("release tag must use exact vMAJOR.MINOR.PATCH format")
    toc_path = root / f"{ADDON_NAME}.toc"
    toc = toc_path.read_text(encoding="utf-8")
    toc_version = _toc_field(toc, "Version")
    if tag != f"v{toc_version}":
        raise ReleaseMetadataError(
            f"release tag {tag} does not match TOC version {toc_version}"
        )

    archive_name = f"{ADDON_NAME}-{tag}.zip"
    archive_path = release_dir / archive_name
    if not archive_path.is_file():
        raise ReleaseMetadataError(f"exact-tag archive is missing: {archive_path}")

    interfaces = parse_toc_interfaces(toc)

    return {
        "releases": [
            {
                "name": _display_title(_toc_field(toc, "Title")),
                "version": tag,
                "filename": archive_name,
                "nolib": False,
                "metadata": [
                    {"flavor": "mainline", "interface": interface}
                    for interface in interfaces
                ],
            }
        ]
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--release-dir", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    release_dir = args.release_dir.resolve()
    metadata = build_release_metadata(root, release_dir, args.tag)
    output_path = release_dir / "release.json"
    output_path.write_text(
        json.dumps(metadata, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Created exact-tag release metadata: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
