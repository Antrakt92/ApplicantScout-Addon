from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def test_luals_dependency_lock_is_exact_and_checksum_gated():
    locks = json.loads(_read("scripts/tool-version-locks.json"))
    tool = locks["luaLanguageServer"]
    version = tool["version"]
    windows = tool["windowsX64"]

    assert re.fullmatch(r"\d+\.\d+\.\d+", version)
    assert windows["url"] == (
        "https://github.com/LuaLS/lua-language-server/releases/download/"
        f"{version}/lua-language-server-{version}-win32-x64.zip"
    )
    assert re.fullmatch(r"[0-9a-f]{64}", windows["sha256"])


def test_luals_gate_is_version_locked_and_fails_closed():
    script = _read("scripts/check-lua.ps1")

    assert "tool-version-locks.json" in script
    assert 'Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @("--version")' in script
    assert '"--check=$LuaPath"' in script
    assert '"--checklevel=Warning"' in script
    assert '"--configpath=$ConfigPath"' in script
    assert "([1-9]\\d*) problems? found" in script
    assert "did not report a successful zero-diagnostic result" in script
    assert "Remove-Item -LiteralPath $LogPath" in script


def test_luals_gate_rejects_reported_problem_even_with_zero_exit(tmp_path):
    fake_luals = tmp_path / "fake-luals.cmd"
    fake_luals.write_text(
        "\n".join(
            (
                "@echo off",
                'if "%~1"=="--version" (',
                "  echo 3.18.2-dev",
                "  exit /b 0",
                ")",
                "echo Diagnosis completed, 1 problem found",
                "exit /b 0",
            )
        ),
        encoding="ascii",
    )

    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-File",
            str(REPO_ROOT / "scripts" / "check-lua.ps1"),
            "-LuaLanguageServer",
            str(fake_luals),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "reported 1 diagnostic problem" in result.stdout + result.stderr


def test_branch_ci_downloads_verified_luals_before_diagnostics():
    workflow = _read(".github/workflows/check.yml")
    install = workflow.index("- name: Install pinned LuaLS")
    checksum = workflow.index("Get-FileHash -Algorithm SHA256", install)
    extract = workflow.index("Expand-Archive", install)
    check = workflow.index("- name: Check addon Lua diagnostics", extract)

    assert "scripts\\tool-version-locks.json" in workflow
    assert "Invoke-WebRequest -Uri $Tool.windowsX64.url" in workflow
    assert checksum < extract < check
    assert '"APSCOUT_LUALS=$LuaLS"' in workflow
    assert ".\\scripts\\check-lua.ps1 -LuaLanguageServer $env:APSCOUT_LUALS" in workflow


def test_luals_config_keeps_unknown_global_and_field_diagnostics_enabled():
    config = json.loads(_read("scripts/lua-diagnostics.luarc.json"))
    disabled = set(config.get("diagnostics.disable", []))

    assert config["runtime.version"] == "Lua 5.1"
    assert "undefined-global" not in disabled
    assert "undefined-field" not in disabled
