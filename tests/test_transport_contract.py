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


def test_payload_v6_appends_current_group_roster_after_applicants():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert "string.char(0x06)" in payload_body
    assert "local rosterOut, rosterCount = BuildRosterPayloadRows(" in payload_body
    applicants_idx = payload_body.index("for _, chunk in ipairs(memberOut) do")
    roster_idx = payload_body.index("table.insert(out, _Uint16BE(rosterCount))")
    assert applicants_idx < roster_idx
    assert "for _, chunk in ipairs(rosterOut) do" in payload_body


def test_roster_payload_rows_include_key_summary_and_group_metadata():
    source = _lua_source()
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    assert "GetNumGroupMembers()" in roster_body
    assert 'table.insert(rosterOut, string.char(_ClampUInt8(row.unitIndex)))' in roster_body
    assert 'table.insert(rosterOut, string.char(_ClampUInt8(row.flags)))' in roster_body
    assert 'table.insert(rosterOut, string.char(_ClampUInt8(row.subgroup)))' in roster_body
    assert "_GetRaiderIOMPlusSummary(" in roster_body
    assert "rioSummary.bestDungeonKey" in roster_body
    assert "_PackLenStr(rosterOut, row.name)" in roster_body
    assert "emittedCount = emittedCount + 1" in roster_body


def test_roster_dirty_events_are_registered():
    source = _lua_source()
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    assert 'GROUP_ROSTER_UPDATE              = function() MarkDirty("roster") end' in events_body
    assert (
        'PLAYER_SPECIALIZATION_CHANGED      = function() MarkDirty("spec") end'
        in events_body
    )


def test_listing_key_level_does_not_fall_back_to_owned_keystone_level():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )
    status_body = _slice_between(
        source,
        'elseif msg == "status" then',
        'elseif msg == "taintcheck" then',
    )

    assert helper_body.startswith(
        "local function _GetListingKeystoneLevel(activityID, questID, listingName, listingComment, activityInfo)"
    )
    assert "ownedLevel" not in helper_body
    assert "shouldUseOwnedKeystone and ownedLevel or 0" not in payload_body
    assert "statusUseOwned and ownedLevel or 0" not in status_body


def test_listing_key_level_prefers_visible_posted_level_over_activity_text():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )

    name_idx = helper_body.index("_ExtractKeystoneLevelFromShortKeyText(listingName)")
    comment_idx = helper_body.index("_ExtractKeystoneLevelFromText(listingComment)")
    visible_idx = helper_body.index("_GetVisibleApplicationViewerKeystoneLevel()")
    cached_idx = helper_body.index("_GetCachedEntryCreationKeystoneLevel(activityID, questID)")
    short_idx = helper_body.index("_ExtractKeystoneLevelFromText(activityShortName)")
    full_idx = helper_body.index("_ExtractKeystoneLevelFromText(activityFullName)")

    assert "GetKeystoneForActivity(" not in helper_body
    assert name_idx < comment_idx < visible_idx < cached_idx < short_idx < full_idx


def test_listing_key_level_uses_active_creation_form_cache():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )
    creation_body = source[
        source.index("local function _RememberEntryCreationKeystoneLevel(panel, reason)") :
    ]
    helper_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )

    assert "entryCreationKeyLevelCache" in source
    assert "_HookEntryCreationKeyCapture(frame.EntryCreation" in source
    assert ':HookScript("OnClick", function()' in creation_body
    assert "panel.Name" in creation_body
    assert "panel.Description" in creation_body
    assert "_ExtractKeystoneLevelFromShortKeyText(nameText)" in creation_body
    assert "_ExtractKeystoneLevelFromText(commentText)" in creation_body
    assert "_GetCachedEntryCreationKeystoneLevel(activityID, questID)" in helper_body
    assert "_GetListingKeystoneLevel(" in payload_body
    assert "activityID,\n                questID,\n                listingName" in payload_body


def test_entry_creation_cache_clears_when_posted_key_cannot_be_read():
    source = _lua_source()
    creation_body = _slice_between(
        source,
        "local function _RememberEntryCreationKeystoneLevel(panel, reason)",
        "local function _HookEntryCreationKeyCapture(panel)",
    )

    assert "local questID = math.floor(SafeNumber(panel.questID, 0))" in creation_body
    assert "if keyLevel == 0 then" in creation_body
    assert "_ClearEntryCreationKeystoneLevelCache(activityID, questID)" in creation_body
    assert creation_body.index("_ClearEntryCreationKeystoneLevelCache(activityID, questID)") < (
        creation_body.index("entryCreationKeyLevelCache = {")
    )


def test_listing_key_level_accepts_short_visible_key_titles_only():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _ExtractKeystoneLevelFromShortKeyText(value)",
        "local function _GetVisibleApplicationViewerKeystoneLevel()",
    )
    listing_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )
    visible_body = _slice_between(
        source,
        "local function _GetVisibleApplicationViewerKeystoneLevel()",
        "local function _GetListingKeystoneLevel(",
    )

    assert "_ExtractKeystoneLevelFromText(value)" in helper_body
    assert "#s > 40" in helper_body
    assert 'local digits = s:gsub("%D+", "")' in helper_body
    assert "#digits < 1 or #digits > 2" in helper_body
    assert "_NormalizeKeystoneLevel(digits)" in helper_body
    assert "_ExtractKeystoneLevelFromShortKeyText(listingName)" in listing_body
    assert "_ExtractKeystoneLevelFromText(listingComment)" in listing_body
    assert "_ExtractKeystoneLevelFromShortKeyText(text)" in visible_body


def test_listing_key_level_can_read_clean_application_viewer_text():
    source = _lua_source()
    visible_body = _slice_between(
        source,
        "local function _GetVisibleApplicationViewerKeystoneLevel()",
        "local function _GetListingKeystoneLevel(",
    )
    helper_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )
    status_body = _slice_between(
        source,
        'elseif msg == "status" then',
        'elseif msg == "taintcheck" then',
    )

    assert "LFGListFrame" in visible_body
    assert "ApplicationViewer" in visible_body
    assert "viewer:IsShown()" in visible_body
    assert "EntryName" in visible_body
    assert "DescriptionFrame.Text" in visible_body
    assert "IsSecretValue(text)" in visible_body
    assert "fontString = viewer.EntryName" in visible_body
    assert (
        "fontString = viewer.DescriptionFrame and viewer.DescriptionFrame.Text"
        in visible_body
    )
    assert "_GetVisibleApplicationViewerKeystoneLevel()" in helper_body
    assert "visibleFrame.keyLevel" in status_body
    assert "visibleFrame.viewerShown" in source
    assert "ApplicantScout_VisibleApplicationViewerKeystoneDiagnostics" in status_body
    assert "entryCreationCache.keyLevel" in status_body


def test_listing_key_level_is_derived_before_owned_keystone_activity_fallback():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    key_idx = payload_body.index("keyLevel = _GetListingKeystoneLevel(")
    owned_idx = payload_body.index("if shouldUseOwnedKeystone then")

    assert key_idx < owned_idx


def test_payload_does_not_pack_raiderio_dungeon_rows_into_qr():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert "_PackRaiderIODungeonRows" not in source
    assert "rio_row_count" not in payload_body
    assert "rioSummary.dungeons" not in payload_body
    assert "_PackLenStr(memberOut, memberName)" in payload_body


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


def test_raiderio_summary_reports_best_keys_from_timed_runs_only():
    source = _lua_source()
    summary_body = _slice_between(
        source,
        "local function _GetRaiderIOMPlusSummary(memberName, listingActivityID, targetKey)",
        "-- CRC32 IEEE-802.3",
    )

    assert "local timed = chests > 0" in summary_body
    assert "if timed and keyLevel > summary.bestKey then" in summary_body
    assert "and _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)" in summary_body


def test_raiderio_lookup_qualifies_same_realm_bare_applicant_names():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _RaiderIOProfileLookupName(memberName)",
        "local function _GetRaiderIOMPlusSummary(memberName, listingActivityID, targetKey)",
    )
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs)",
        "local function HashSnapshot(payload)",
    )

    assert 'memberName:find("-", 1, true)' in helper_body
    assert 'UnitFullName("player")' in helper_body
    assert '"-" .. playerRealm' in helper_body
    summary_idx = payload_body.index("local rioSummary = _GetRaiderIOMPlusSummary(")
    lookup_idx = payload_body.index("_RaiderIOProfileLookupName(memberName)")
    activity_idx = payload_body.index("listingActivityIDForRio", lookup_idx)
    assert summary_idx < lookup_idx < activity_idx
    assert "_PackLenStr(memberOut, memberName)" in payload_body
