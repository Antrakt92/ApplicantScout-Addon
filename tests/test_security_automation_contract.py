from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_dependabot_covers_pinned_github_actions_on_a_bounded_schedule():
    config = _read(".github/dependabot.yml")

    assert config.count('package-ecosystem: "github-actions"') == 1
    assert config.count('directory: "/"') == 1
    assert config.count('interval: "weekly"') == 1
    assert config.count("open-pull-requests-limit: 5") == 1


def test_security_policy_documents_the_codeql_lua_boundary_and_existing_gates():
    policy = _read("SECURITY.md")

    assert "CodeQL does not support Lua" in policy
    assert "LuaLS" in policy
    assert "Lua 5.1" in policy
    assert "ApplicantScout-Companion" in policy
