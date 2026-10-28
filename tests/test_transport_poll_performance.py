from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_pending_drain_and_periodic_poll_share_one_payload_build(pytestconfig):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for transport workload checks"
    result = subprocess.run(
        [lua, str(ROOT / "tests/lua/check_transport_poll_coalescing.lua")],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip().endswith("ok transport-poll-coalescing bytes=3837")
