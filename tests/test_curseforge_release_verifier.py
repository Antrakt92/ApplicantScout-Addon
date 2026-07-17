from __future__ import annotations

from collections.abc import Mapping
from typing import Any

import pytest

from scripts.verify_curseforge_release import (
    MarketplaceVerificationError,
    evaluate_public_files,
    expected_file_name,
    parse_public_files,
    wait_for_public_release,
)


PROJECT_ID = 1541576
EXPECTED_NAME = "ApplicantScout-v0.5.3.zip"
REQUIRED_VERSIONS = frozenset({"12.0.7", "12.1.0"})


def _file(
    name: str = EXPECTED_NAME,
    *,
    file_id: int = 9000000,
    status: int = 4,
    versions: list[str] | None = None,
) -> dict[str, object]:
    return {
        "id": file_id,
        "fileName": name,
        "projectId": PROJECT_ID,
        "status": status,
        "gameVersions": versions or ["12.0.7", "12.1.0"],
    }


def _evaluate(files: list[Mapping[str, Any]]) -> tuple[bool, str]:
    return evaluate_public_files(
        files,
        project_id=PROJECT_ID,
        expected_name=EXPECTED_NAME,
        required_game_versions=REQUIRED_VERSIONS,
    )


def test_expected_file_name_requires_strict_semver_tag():
    assert expected_file_name("v0.5.3") == EXPECTED_NAME
    assert expected_file_name("0.5.3") == EXPECTED_NAME

    with pytest.raises(MarketplaceVerificationError, match="strict"):
        expected_file_name("v0.5")


def test_parse_public_files_accepts_list_and_data_wrapper():
    item = _file()

    assert parse_public_files([item]) == [item]
    assert parse_public_files({"data": [item]}) == [item]

    with pytest.raises(MarketplaceVerificationError, match="not a list"):
        parse_public_files({"data": {}})


def test_public_release_requires_first_approved_file_and_game_versions():
    ready, message = _evaluate([_file()])

    assert ready is True
    assert "status=4 Approved" in message


@pytest.mark.parametrize("status", (1, 3, 9, 14, 19, 21, 23))
def test_public_release_waits_for_nonterminal_status(status: int):
    ready, message = _evaluate([_file(status=status)])

    assert ready is False
    assert f"status {status}" in message


@pytest.mark.parametrize("status", (2, 5, 6, 7, 8, 12, 15))
def test_public_release_rejects_terminal_status(status: int):
    with pytest.raises(MarketplaceVerificationError, match="terminal"):
        _evaluate([_file(status=status)])


def test_public_release_waits_until_expected_file_is_first():
    ready, message = _evaluate(
        [_file("ApplicantScout-v0.5.4.zip", file_id=9000001), _file()]
    )

    assert ready is False
    assert "not the first" in message


def test_public_release_waits_for_required_game_versions():
    ready, message = _evaluate([_file(versions=["12.0.7"])])

    assert ready is False
    assert "12.1.0" in message


def test_waiter_recovers_from_pending_feed_without_reuploading():
    payloads = [
        [_file("ApplicantScout-v0.5.2.zip", file_id=8439768)],
        [_file(status=3)],
        [_file()],
    ]
    clock = iter((0.0, 0.0, 1.0, 2.0))

    def fetch(_project_id: int, *, request_timeout: float):
        assert request_timeout == 20.0
        return payloads.pop(0)

    message = wait_for_public_release(
        project_id=PROJECT_ID,
        expected_name=EXPECTED_NAME,
        required_game_versions=REQUIRED_VERSIONS,
        wait_seconds=10.0,
        poll_seconds=1.0,
        request_timeout=20.0,
        fetch=fetch,
        monotonic=lambda: next(clock),
        sleep=lambda _seconds: None,
    )

    assert "first public file" in message
    assert payloads == []


def test_waiter_timeout_explains_that_only_verification_is_safe_to_rerun():
    clock = iter((0.0, 0.0, 1.0))

    with pytest.raises(MarketplaceVerificationError, match="Rerun only this"):
        wait_for_public_release(
            project_id=PROJECT_ID,
            expected_name=EXPECTED_NAME,
            required_game_versions=REQUIRED_VERSIONS,
            wait_seconds=1.0,
            poll_seconds=1.0,
            request_timeout=20.0,
            fetch=lambda _project_id, request_timeout: [],
            monotonic=lambda: next(clock),
            sleep=lambda _seconds: None,
        )
