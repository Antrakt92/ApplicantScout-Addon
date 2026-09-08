from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
    "scenario", ["first-run", "watcher-first", "dismissed", "disabled", "corrupt", "combat"]
)
def test_companion_setup_lifecycle(pytestconfig, scenario):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup lifecycle tests"
    result = subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), scenario],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip().endswith(f"ok {scenario}")
