from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
    "scenario",
    [
        "first-run", "watcher-first", "dismissed", "disabled", "corrupt", "combat",
        "postponed", "small-display", "font-switch", "font-missing", "font-error",
        "font-partial", "font-false-success", "font-nil-return", "font-cold", "escape", "resize",
        "parent-hide", "measurement-invalid", "measurement-error",
        "retry-interaction",
        "measurement-zero", "measurement-negative",
        "font-all-missing", "enabled-transition",
        "resume-step", "legacy-dismissed", "explicit-reminder", "scrollbar", "settings-font",
    ],
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


@pytest.mark.parametrize("locale", ["ruRU", "frFR", "koKR", "zhCN", "zhTW"])
def test_setup_compatible_fallback_keeps_the_selected_language(pytestconfig, locale):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup language tests"
    subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), "font-compatible-fallback", locale],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )


@pytest.mark.parametrize("locale", ["enUS", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"])
@pytest.mark.parametrize("step", [1, 2, 3, 4, 5])
def test_setup_step_actions_details_and_control_bounds(pytestconfig, locale, step):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup design tests"
    subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), "design", locale, str(step)],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )


@pytest.mark.parametrize("scenario", ["saved-step", "saved-step-zero", "saved-step-high", "saved-step-fraction", "saved-step-nan", "saved-step-string", "saved-step-table"])
def test_setup_saved_progress_is_validated(pytestconfig, scenario):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup progress tests"
    subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), scenario, "ruRU"],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )


@pytest.mark.parametrize("locale", [
    "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU",
    "koKR", "zhCN", "zhTW", "unknown",
])
@pytest.mark.parametrize("scenario", [
    "language", "language-saved", "language-invalid", "language-invalid-string",
])
def test_setup_language_detection_switch_and_reload(pytestconfig, locale, scenario):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup language tests"
    result = subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), scenario, locale],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )
    assert result.stdout.strip().endswith(f"ok {scenario} {locale}")


@pytest.mark.parametrize("scenario", ["locale-api-error", "locale-api-missing"])
def test_setup_locale_api_failure_uses_english(pytestconfig, scenario):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup language tests"
    subprocess.run(
        [lua, str(ROOT / "tests/lua/check_companion_setup.lua"), scenario, "frFR"],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )


def test_every_supported_setup_translation_is_complete(pytestconfig):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua, "Lua 5.1 is required for setup translation validation"
    subprocess.run(
        [lua, str(ROOT / "tests/lua/check_setup_translations.lua")],
        cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8",
    )


def test_setup_translations_load_before_runtime_and_are_packaged():
    toc = (ROOT / "ApplicantScout.toc").read_text(encoding="utf-8")
    assert toc.index("SetupLocales.lua") < toc.index("ApplicantScout.lua")
    package_script = (ROOT / "scripts/package-addon.ps1").read_text(encoding="utf-8")
    assert '"SetupLocales.lua"' in package_script


@pytest.mark.parametrize("locale", ["enUS", "ruRU", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "koKR", "zhCN", "zhTW"])
def test_addon_menu_settings_and_lifecycle(pytestconfig, locale):
    lua = pytestconfig.getoption("--lua51") or shutil.which("lua5.1")
    assert lua
    subprocess.run([lua, str(ROOT / "tests/lua/check_companion_setup.lua"), "menu", locale],
                   cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8")
