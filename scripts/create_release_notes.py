"""Create GitHub release notes for one exact ApplicantScout release tag."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


_SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
_SEMVER_TAG = re.compile(rf"^v(?P<version>{_SEMVER})$")
_LEVEL_TWO_HEADING = re.compile(
    r"(?m)^##[ \t]+(?P<title>[^\n]*\S)[ \t]*$"
)
_RELEASE_HEADING = re.compile(
    rf"^(?P<version>{_SEMVER})[ \t]+-[ \t]+\S.*$"
)


class ReleaseNotesError(ValueError):
    """The changelog cannot produce notes for the requested exact tag."""


def extract_release_notes(changelog: str, tag: str) -> str:
    """Return only the current version section for an exact release tag."""
    tag_match = _SEMVER_TAG.fullmatch(tag)
    if tag_match is None:
        raise ReleaseNotesError(
            "release tag must use exact vMAJOR.MINOR.PATCH format"
        )
    target_version = tag_match.group("version")

    normalized = changelog.replace("\r\n", "\n").replace("\r", "\n")
    headings = list(_LEVEL_TWO_HEADING.finditer(normalized))
    unreleased = [
        heading for heading in headings if heading.group("title") == "Unreleased"
    ]
    if len(unreleased) != 1:
        raise ReleaseNotesError(
            "CHANGELOG must contain exactly one level-two Unreleased section"
        )
    if not headings or headings[0] is not unreleased[0]:
        raise ReleaseNotesError(
            "Unreleased must be the first level-two CHANGELOG section"
        )

    releases: list[tuple[re.Match[str], re.Match[str]]] = []
    for heading in headings[1:]:
        release = _RELEASE_HEADING.fullmatch(heading.group("title"))
        if release is None:
            raise ReleaseNotesError(
                "every level-two section after Unreleased must be a versioned release"
            )
        releases.append((heading, release))

    if not releases:
        raise ReleaseNotesError("CHANGELOG has no released version section")
    current_heading, current_release = releases[0]
    current_version = current_release.group("version")
    if current_version != target_version:
        raise ReleaseNotesError(
            f"CHANGELOG top release is {current_version}, expected {target_version}"
        )
    if sum(
        release.group("version") == target_version for _, release in releases
    ) != 1:
        raise ReleaseNotesError(
            f"CHANGELOG must contain exactly one release section for {target_version}"
        )

    end = headings[2].start() if len(headings) > 2 else len(normalized)
    section = normalized[current_heading.start() : end].strip()
    content_lines = section.splitlines()[1:]
    visible_copy = re.sub(
        r"<!--.*?-->",
        "",
        "\n".join(content_lines),
        flags=re.DOTALL,
    )
    if not any(
        line.strip()
        and not line.lstrip().startswith("#")
        and re.fullmatch(r"[ \t]{0,3}(?:[-*_][ \t]*){3,}", line) is None
        for line in visible_copy.splitlines()
    ):
        raise ReleaseNotesError(
            f"CHANGELOG release section {target_version} has no release copy"
        )
    return section + "\n"


def write_release_notes(
    changelog_path: Path,
    output_path: Path,
    tag: str,
) -> None:
    notes = extract_release_notes(
        changelog_path.read_text(encoding="utf-8"),
        tag,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(notes, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    write_release_notes(args.changelog, args.output, args.tag)
    print(f"Created exact-version release notes: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
