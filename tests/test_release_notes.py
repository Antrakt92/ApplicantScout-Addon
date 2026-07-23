from __future__ import annotations

from pathlib import Path

import pytest

from scripts.create_release_notes import (
    ReleaseNotesError,
    extract_release_notes,
    write_release_notes,
)


def _changelog(
    *,
    current_version: str = "1.2.3",
    current_copy: str = "- Fixed the current release.",
    older_version: str = "1.2.2",
) -> str:
    return (
        "# Changelog\n\n"
        "## Unreleased\n\n"
        "- Future work.\n\n"
        f"## {current_version} - 22-Jul-2026 - Current release\n\n"
        f"{current_copy}\n\n"
        f"## {older_version} - 21-Jul-2026 - Older release\n\n"
        "- Historical work.\n"
    )


def test_release_notes_include_only_the_exact_current_version():
    notes = extract_release_notes(_changelog(), "v1.2.3")

    assert notes.startswith("## 1.2.3 - 22-Jul-2026 - Current release\n")
    assert "Fixed the current release" in notes
    assert "Unreleased" not in notes
    assert "Future work" not in notes
    assert "1.2.2" not in notes
    assert "Historical work" not in notes
    assert notes.endswith("\n")


def test_release_notes_writer_normalizes_newlines(tmp_path: Path):
    changelog = tmp_path / "CHANGELOG.md"
    output = tmp_path / "nested" / "release-notes.md"
    changelog.write_bytes(_changelog().replace("\n", "\r\n").encode())

    write_release_notes(changelog, output, "v1.2.3")

    assert output.read_bytes() == extract_release_notes(
        _changelog(), "v1.2.3"
    ).encode()


@pytest.mark.parametrize("tag", ["1.2.3", "v01.2.3", "v1.2.3-beta"])
def test_release_notes_reject_noncanonical_tag(tag: str):
    with pytest.raises(ReleaseNotesError, match="exact vMAJOR"):
        extract_release_notes(_changelog(), tag)


@pytest.mark.parametrize(
    ("changelog", "tag", "message"),
    [
        (_changelog(current_version="1.2.4"), "v1.2.3", "top release is 1.2.4"),
        (_changelog(), "v1.2.2", "top release is 1.2.3"),
        (_changelog(), "v1.2.4", "top release is 1.2.3"),
        (_changelog(current_copy="### Fixed"), "v1.2.3", "no release copy"),
        (
            _changelog(current_copy="<!-- TODO: write notes -->\n\n---"),
            "v1.2.3",
            "no release copy",
        ),
        (
            _changelog() + "\n## 1.2.3 - 20-Jul-2026 - Duplicate\n\n- Copy.\n",
            "v1.2.3",
            "exactly one release section",
        ),
        (
            _changelog().replace("## Unreleased", "## Planned"),
            "v1.2.3",
            "exactly one level-two Unreleased",
        ),
        (
            _changelog().replace(
                "## 1.2.2 - 21-Jul-2026 - Older release",
                "## Historical notes",
            ),
            "v1.2.3",
            "every level-two section",
        ),
    ],
)
def test_release_notes_reject_ambiguous_or_wrong_version_copy(
    changelog: str,
    tag: str,
    message: str,
):
    with pytest.raises(ReleaseNotesError, match=message):
        extract_release_notes(changelog, tag)
