from pathlib import Path
import shutil
import subprocess

import pytest


@pytest.mark.parametrize("mode", ["expiry", "reset", "session", "listing"])
def test_applicant_member_cache_refreshes_without_roster_changes(pytestconfig, mode):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required"
    result = subprocess.run(
        [lua, "tests/lua/check_applicant_cache_freshness.lua", mode],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.strip() == f"ok applicant-cache-freshness {mode}"
