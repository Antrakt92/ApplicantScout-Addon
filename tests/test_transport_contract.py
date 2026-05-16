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
    assert "_ReleaseForceVisibleShotLease(forceVisibleShotGen)" in screenshot_body
    assert "qrForceVisibleForShot = false" in source


def test_force_screenshot_releases_visibility_lease_when_qr_encode_fails():
    source = _lua_source()
    body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    matrix_fail = _slice_between(body, "if not matrix then", "if not PaintQR(matrix) then")
    paint_fail = _slice_between(body, "if not PaintQR(matrix) then", "lastShotTime = now")

    assert "_ReleaseForceVisibleShotLease(forceVisibleShotGen)" in matrix_fail
    assert "_ReleaseForceVisibleShotLease(forceVisibleShotGen)" in paint_fail


def test_safe_str_strips_player_links_before_bare_pipe_cleanup():
    source = _lua_source()
    body = _slice_between(source, "SafeStr = function(v, secretFallback)", "local function SafeDiag")

    player_link_idx = body.index('s = s:gsub("|K[^|]*|k", "")')
    bare_pipe_idx = body.index('s = s:gsub("|", "")')

    assert player_link_idx < bare_pipe_idx


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
    screenshot_idx = body.index("MaybeTriggerScreenshot(true")

    assert disabled_guard_idx < screenshot_idx
    assert "return" in body[disabled_guard_idx:screenshot_idx]


def test_shotnow_refreshes_session_before_forced_snapshot():
    source = _lua_source()
    body = _slice_between(
        source,
        'elseif msg == "shotnow" then',
        'elseif msg == "qrvisible" then',
    )

    transition_idx = body.index("CheckSessionTransition()")
    screenshot_idx = body.index("MaybeTriggerScreenshot(true")

    assert transition_idx < screenshot_idx


def test_payload_still_includes_raiderio_completion_summary():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert "string.char(0x06)" in payload_body
    assert "_GetRaiderIOMPlusSummary(" in source
    assert "rioSummary.hasProfile" in payload_body
    assert "rioSummary.bestDungeonKey" in payload_body


def test_payload_uses_wire_v6_with_raiderio_dungeon_rows():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert "string.char(0x06)" in payload_body
    assert "v6: RaiderIO dungeon rows" in payload_body
    assert "rioSummary.dungeons" in payload_body
    assert "_PackRaiderIODungeonRows(memberOut, rioSummary.dungeons)" in payload_body
    packer_body = _slice_between(
        source,
        "local function _PackRaiderIODungeonRows(out, rows)",
        "-- CRC32 IEEE-802.3",
    )
    assert "string.char(_ClampUInt8(keyLevel))" in packer_body
    assert "_PackLenStr(chunks, name)" in packer_body
    assert "timed" not in packer_body.casefold()
    assert "depleted" not in packer_body.casefold()


def test_raiderio_summary_reuses_one_profile_lookup_per_member():
    source = _lua_source()
    summary_body = _slice_between(
        source,
        "local function _GetRaiderIOMPlusSummary(memberName, listingActivityID, targetKey)",
        "-- CRC32 IEEE-802.3",
    )
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert summary_body.count("pcall(rio.GetProfile") == 1
    assert payload_body.count("_GetRaiderIOMPlusSummary(") == 1
    assert "_RaiderIODungeonMatchesActivity" in summary_body
