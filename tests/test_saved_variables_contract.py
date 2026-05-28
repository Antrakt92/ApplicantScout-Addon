from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
LUA_DB_CHECK = REPO_ROOT / "tests" / "lua" / "check_db_boolean_normalization.lua"


def _lua51_path(pytestconfig):
    raw_lua = pytestconfig.getoption("--lua51")
    lua = raw_lua or shutil.which("lua5.1")
    assert lua is not None, (
        "lua5.1 is required for Lua SavedVariables contract tests; "
        "pass --lua51 <path>"
    )
    return lua


def _run_db_check(pytestconfig, scenario: str) -> str:
    result = subprocess.run(
        [_lua51_path(pytestconfig), str(LUA_DB_CHECK), scenario],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def test_initdb_normalizes_corrupt_boolean_saved_variables(pytestconfig):
    assert _run_db_check(pytestconfig, "corrupt") == "ok corrupt"


def test_initdb_preserves_new_install_defaults_as_strict_booleans(pytestconfig):
    assert _run_db_check(pytestconfig, "defaults") == "ok defaults"


def test_initdb_migrates_legacy_competitive_boolean_safely(pytestconfig):
    assert _run_db_check(pytestconfig, "legacy-false") == "ok legacy-false"
    assert _run_db_check(pytestconfig, "legacy-true") == "ok legacy-true"


def test_initdb_fails_closed_for_wrong_type_booleans(pytestconfig):
    assert _run_db_check(pytestconfig, "wrong-types") == "ok wrong-types"
