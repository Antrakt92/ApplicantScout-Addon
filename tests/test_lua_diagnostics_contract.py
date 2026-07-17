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
    assert '"--check=$WorkspacePath"' in script
    assert '"--checklevel=Warning"' in script
    assert '"--configpath=$ConfigPath"' in script
    assert '"types\\wow-globals.d.lua"' in script
    assert "Copy-Item -LiteralPath $LuaPath" in script
    assert "Copy-Item -LiteralPath $TypesPath" in script
    assert "([1-9]\\d*) problems? found" in script
    assert "did not report a successful zero-diagnostic result" in script
    assert "ApplicantScoutIntentionalUndefinedGlobal" in script
    assert "did not detect the intentional undefined global" in script
    assert "Remove-Item -LiteralPath $WorkspacePath" in script
    assert "Remove-Item -LiteralPath $LogRoot" in script


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


def test_luals_gate_rejects_an_insensitive_clean_reporter(tmp_path):
    fake_luals = tmp_path / "fake-luals.cmd"
    fake_luals.write_text(
        "\n".join(
            (
                "@echo off",
                'if "%~1"=="--version" (',
                "  echo 3.18.2-dev",
                "  exit /b 0",
                ")",
                "echo Diagnosis completed, no problems found",
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
    assert "did not detect the intentional undefined global" in (
        result.stdout + result.stderr
    )


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


def test_release_preflight_runs_the_pinned_sensitive_luals_gate_before_upload():
    workflow = _read(".github/workflows/release.yml")
    preflight = workflow.index("  preflight:")
    install = workflow.index("- name: Install pinned LuaLS", preflight)
    checksum = workflow.index("Get-FileHash -Algorithm SHA256", install)
    extract = workflow.index("Expand-Archive", install)
    diagnostics = workflow.index("- name: Check addon Lua diagnostics", extract)
    paired = workflow.index("- name: Check paired companion and addon contracts", diagnostics)
    writer = workflow.index("  release:", paired)

    assert "scripts\\tool-version-locks.json" in workflow[install:diagnostics]
    assert checksum < extract < diagnostics < paired < writer
    assert (
        ".\\scripts\\check-lua.ps1 -LuaLanguageServer $env:APSCOUT_LUALS"
        in workflow[diagnostics:paired]
    )


def test_luals_config_keeps_unknown_global_and_field_diagnostics_enabled():
    config = json.loads(_read("scripts/lua-diagnostics.luarc.json"))
    disabled = set(config.get("diagnostics.disable", []))
    globals_ = set(config.get("diagnostics.globals", []))

    assert config["runtime.version"] == "Lua 5.1"
    assert "undefined-global" not in disabled
    assert "undefined-field" not in disabled
    for name in (
        "C_LFGList",
        "C_Timer",
        "CreateFrame",
        "Screenshot",
        "UnitGUID",
    ):
        assert name in globals_
    assert "ApplicantScoutIntentionalUndefinedGlobal" not in globals_


def test_luals_workspace_owns_exact_wow_global_declarations():
    declarations = _read("scripts/types/wow-globals.d.lua")

    assert declarations.startswith("---@meta\n")
    for name in (
        "hooksecurefunc",
        "LFGListFrame",
        "PVEFrame",
        "UNKNOWNOBJECT",
    ):
        assert re.search(rf"(?:function {name}\b|\n{name} = )", declarations)
    assert "---@field [" not in declarations
    assert "__index" not in declarations
