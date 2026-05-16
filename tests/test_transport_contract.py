from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _lua_source() -> str:
    return (REPO_ROOT / "ApplicantScout.lua").read_text(encoding="utf-8")


def _slice_between(text: str, start: str, end: str) -> str:
    start_idx = text.index(start)
    end_idx = text.index(end, start_idx)
    return text[start_idx:end_idx]


def test_non_force_screenshot_waits_until_qr_is_visible_before_payload_dedup():
    source = _lua_source()
    body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    guard_idx = body.index("not _IsQRVisibleForScreenshot()")
    payload_idx = body.index("local payload = BuildPayload(entry, applicantIDs)")
    hash_idx = body.index("local h = HashSnapshot(payload)")
    guard_block = body[guard_idx : body.index("\n    end", guard_idx)]

    assert guard_idx < payload_idx < hash_idx
    assert "pendingShotDirty = true" in guard_block
    assert "return" in guard_block


def test_force_screenshot_temporarily_makes_hidden_qr_visible_for_clear_shot():
    source = _lua_source()
    visibility_body = _slice_between(
        source,
        "_RefreshQRVisibility = function()",
        "_IsQRVisibleForScreenshot = function()",
    )
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    assert "or qrForceVisibleForShot" in visibility_body
    assert "force and not _IsQRVisibleForScreenshot()" in screenshot_body
    assert "qrForceVisibleForShot = true" in screenshot_body
    assert "forceVisibleShotDelay = QR_RENDER_SETTLE_S" in screenshot_body
    assert "qrForceVisibleForShot = false" in screenshot_body


def test_default_playstyle_checks_secret_activity_before_nil_comparison():
    source = _lua_source()
    body = _slice_between(
        source,
        "_MaybeAutoSelectDefaultPlaystyle = function(panel, reason)",
        "_SetupLFGDefaultPlaystyle = function()",
    )

    activity_read_idx = body.index("local activityID = panel.selectedActivity")
    secret_guard_idx = body.index("IsSecretValue(activityID)")
    nil_compare_idx = body.index("activityID == nil")

    assert activity_read_idx < secret_guard_idx < nil_compare_idx


def test_pve_frame_drag_requires_alt_modifier():
    source = _lua_source()
    body = _slice_between(
        source,
        "local function _OnPVEFrameDragStart()",
        "local function _OnPVEFrameDragStop()",
    )

    combat_guard_idx = body.index("InCombatLockdown()")
    alt_guard_idx = body.index("not IsAltKeyDown()")
    start_moving_idx = body.index("PVEFrame:StartMoving()")

    assert combat_guard_idx < alt_guard_idx < start_moving_idx


def test_shotnow_is_gated_when_addon_is_disabled():
    source = _lua_source()
    body = _slice_between(
        source,
        'elseif msg == "shotnow" then',
        'elseif msg == "qrvisible" then',
    )

    disabled_guard_idx = body.index("not (ApplicantScoutDB and ApplicantScoutDB.enabled)")
    screenshot_idx = body.index("MaybeTriggerScreenshot(true)")

    assert disabled_guard_idx < screenshot_idx
    assert "return" in body[disabled_guard_idx:screenshot_idx]
