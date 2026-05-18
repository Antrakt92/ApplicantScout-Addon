from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _lua_source() -> str:
    return (REPO_ROOT / "ApplicantScout.lua").read_text(encoding="utf-8")


def _slice_between(text: str, start: str, end: str) -> str:
    start_idx = text.index(start)
    end_idx = text.index(end, start_idx)
    return text[start_idx:end_idx]


def test_non_force_screenshot_uses_transient_qr_lease_after_paint():
    source = _lua_source()
    body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    payload_idx = body.index("local payload = BuildPayload(entry, applicantIDs)")
    hash_idx = body.index("local h = HashSnapshot(payload)")
    matrix_idx = body.index("local matrix = BuildQRMatrix(payload)")
    paint_idx = body.index("if not PaintQR(matrix) then")
    lease_idx = body.index("local forceVisibleShotGen, forceVisibleShotDelay = _AcquireQRShotLease()")
    screenshot_idx = body.index("        Screenshot()")

    assert payload_idx < hash_idx < matrix_idx < paint_idx < lease_idx < screenshot_idx
    assert "_ReleaseForceVisibleShotLease(forceVisibleShotGen)" in body[screenshot_idx:]


def test_session_visibility_does_not_keep_qr_on_screen_between_shots():
    source = _lua_source()
    visibility_body = _slice_between(
        source,
        "_RefreshQRVisibility = function()",
        "_IsQRVisibleForScreenshot = function()",
    )

    assert "isSessionActive and not _qrSuppressedByInteraction" not in visibility_body
    assert "qrAlwaysVisible\n                       or qrMoveMode\n                       or qrForceVisibleForShot" in visibility_body


def test_interaction_suppression_defers_non_force_payloads_before_dedup():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    suppression_idx = screenshot_body.index("not force and _qrSuppressedByInteraction")
    payload_idx = screenshot_body.index("local payload = BuildPayload(entry, applicantIDs)")
    suppression_block = screenshot_body[
        suppression_idx : screenshot_body.index("\n    end", suppression_idx)
    ]

    assert suppression_idx < payload_idx
    assert "pendingShotDirty = true" in suppression_block
    assert "return" in suppression_block


def test_qr_shot_lease_shows_hidden_qr_and_releases_after_capture():
    source = _lua_source()
    lease_body = _slice_between(
        source,
        "local function _AcquireQRShotLease()",
        "-- Build payload, dedup vs last hash, throttle, paint QR, trigger Screenshot.",
    )

    assert "qrForceVisibleForShot = true" in lease_body
    assert "qrForceVisibleShotGen = (qrForceVisibleShotGen or 0) + 1" in lease_body
    assert "_RefreshQRVisibility()" in lease_body
    assert "QR_RENDER_SETTLE_S" in lease_body
    assert "qrForceVisibleForShot = false" in source


def test_party_roster_starts_transport_without_lfg_listing():
    source = _lua_source()
    transition_body = _slice_between(
        source,
        "CheckSessionTransition = function()",
        "-- Single transition logger",
    )
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint)",
        "-- LFG entry creation",
    )

    assert "local hasRoster = _HasGroupRosterForTransport()" in transition_body
    assert "local transportActive = hosting or hasRoster" in transition_body
    assert "if transportActive and not isSessionActive then" in transition_body
    assert "elseif not transportActive and isSessionActive then" in transition_body
    assert "not isSessionActive and not force" in screenshot_body


def test_entry_creation_cache_clears_when_grouped_listing_ends_without_ending_transport():
    source = _lua_source()
    transition_body = _slice_between(
        source,
        "CheckSessionTransition = function()",
        "-- Single transition logger",
    )

    reconcile_idx = transition_body.index("entryCreationKeyState.ReconcileEntryCreationKeyCache(listingContext)")
    transport_idx = transition_body.index("local transportActive = hosting or hasRoster")
    end_idx = transition_body.index("EndSession()")

    assert "local listingContext = entryCreationKeyState.EntryListingCacheContext(entry)" in transition_body
    assert reconcile_idx < transport_idx < end_idx
    assert "_ClearEntryCreationKeyLevelCache(\"listing-ended\")" in source


def test_same_activity_entry_update_requires_fresh_pending_key_cache():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "entryCreationKeyState.ReconcileEntryCreationKeyCache = function(listingContext)",
        "local function _RememberEntryCreationKeystoneLevel(panel, reason)",
    )

    maybe_idx = helper_body.index("local listingChanged = entryCreationKeyState.activeListingMaybeChanged")
    pending_idx = helper_body.index(
        "_PublishPendingEntryCreationKeyLevelCache(listingContext)",
        maybe_idx,
    )
    stale_idx = helper_body.index("_ClearEntryCreationKeyLevelCache(\"stale-after-entry-update\")")

    assert maybe_idx < pending_idx < stale_idx
    assert "_PublishPendingEntryCreationKeyLevelCache(listingContext)" in helper_body


def test_pending_entry_creation_cache_has_short_promotion_window():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _PublishPendingEntryCreationKeyLevelCache(listingContext)",
        "local function _GetCachedEntryCreationKeystoneLevel(activityID, questID)",
    )

    assert "pendingTtl = 10" in source
    assert "entryCreationKeyState.pendingEntryCreationKeyLevelCache.at" in helper_body
    assert "entryCreationKeyState.pendingTtl" in helper_body
    assert "entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil" in helper_body


def test_scan_ticker_polls_transport_state_when_events_are_missed():
    source = _lua_source()
    ticker_body = _slice_between(
        source,
        "C_Timer.NewTicker(0.25, function()",
        "-- Settings panel:",
    )

    idle_idx = ticker_body.index("if not (scanDirty and ApplicantScoutDB and ApplicantScoutDB.enabled) then")
    poll_idx = ticker_body.index("if ApplicantScoutDB and ApplicantScoutDB.enabled")
    transition_idx = ticker_body.index("local entry = CheckSessionTransition()", poll_idx)
    screenshot_idx = ticker_body.index("MaybeTriggerScreenshot(false, entry)", transition_idx)
    dirty_idx = ticker_body.index("scanDirty = false")

    assert idle_idx < poll_idx < transition_idx < screenshot_idx < dirty_idx
    assert "TRANSPORT_POLL_S" in ticker_body
    assert "not IsChatMessagingLockdown()" in ticker_body[poll_idx:dirty_idx]


def test_transport_poll_does_not_force_unchanged_snapshots():
    source = _lua_source()
    ticker_body = _slice_between(
        source,
        "C_Timer.NewTicker(0.25, function()",
        "-- Settings panel:",
    )

    poll_idx = ticker_body.index("TRANSPORT_POLL_S")
    transition_idx = ticker_body.index("local entry = CheckSessionTransition()", poll_idx)
    non_force_idx = ticker_body.index("MaybeTriggerScreenshot(false, entry)", transition_idx)

    assert "TRANSPORT_HEARTBEAT_S" not in ticker_body
    assert "MaybeTriggerScreenshot(true, entry)" not in ticker_body
    assert transition_idx < non_force_idx


def test_roster_payload_rows_skip_solo_player_when_not_grouped():
    source = _lua_source()
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    group_idx = roster_body.index("local groupCount = math.floor")
    solo_guard_idx = roster_body.index("if groupCount <= 0 then")
    player_idx = roster_body.index('_BuildRosterRow("player", 1, 1, false)')

    assert group_idx < solo_guard_idx < player_idx
    assert "return rosterOut, emittedCount" in roster_body[solo_guard_idx:player_idx]


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


def test_roster_spec_resolution_requests_inspect_when_spec_is_unknown():
    source = _lua_source()
    spec_body = _slice_between(
        source,
        "local function _UnitSpecIDForRoster(unit)",
        "local function _UnitItemLevelForRoster(unit)",
    )

    inspect_idx = spec_body.index("GetInspectSpecialization")
    request_idx = spec_body.index("_MaybeRequestRosterInspect(unit, guid)")
    fallback_idx = spec_body.index("return 0", request_idx)

    assert "rosterInspectSpecByGUID[guid]" in spec_body
    assert inspect_idx < request_idx < fallback_idx


def test_inspect_ready_marks_roster_dirty_after_caching_spec():
    source = _lua_source()
    header_body = _slice_between(
        source,
        "local SafeStr, APSPrint, InitDB, StartSession, EndSession, CheckSessionTransition,",
        "-- Forward-decl mutable state used by StartSession/EndSession/reset.",
    )
    inspect_body = _slice_between(
        source,
        "local function _OnRosterInspectReady(guid)",
        "local function _UnitSpecIDForRoster(unit)",
    )
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    assert "rosterInspectSpecByGUID[guid] = specID" in inspect_body
    assert 'MarkDirty("inspect")' in inspect_body
    assert "MarkDirty" in header_body
    assert "MarkDirty = function(reason)" in source
    assert "local function MarkDirty(reason)" not in source
    assert 'INSPECT_READY                    = function(_, guid)' in events_body
    assert "_OnRosterInspectReady(guid)" in events_body


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


def test_listing_key_level_uses_owned_keystone_only_after_listing_match_guard():
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
    guard_idx = payload_body.index("local shouldUseOwnedKeystone = ownedLevel > 0")
    fallback_idx = payload_body.index("if keyLevel == 0 and shouldUseOwnedKeystone then")
    assert guard_idx < fallback_idx
    assert "keyLevel = ownedLevel" in payload_body[fallback_idx:]
    status_guard_idx = status_body.index("local statusUseOwned = ownedLevel > 0")
    status_fallback_idx = status_body.index(
        "if statusDerivedKeyLevel == 0 and statusUseOwned then"
    )
    assert status_guard_idx < status_fallback_idx
    assert "statusDerivedKeyLevel = ownedLevel" in status_body[status_fallback_idx:]


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


def test_cached_entry_creation_key_requires_known_active_activity():
    source = _lua_source()
    resolver_body = _slice_between(
        source,
        "entryCreationKeyState.ResolveCachedEntryCreationKeystoneLevel = function(activityID, questID)",
        "entryCreationKeyState.PeekCachedEntryCreationKeystoneLevel = function(activityID, questID)",
    )
    getter_body = _slice_between(
        source,
        "local function _GetCachedEntryCreationKeystoneLevel(activityID, questID)",
        "local function _ClearEntryCreationKeystoneLevelCache",
    )

    normalize_idx = resolver_body.index("activityID = math.floor(SafeNumber(activityID, 0))")
    unknown_idx = resolver_body.index("if activityID <= 0 then")
    cache_idx = resolver_body.index("local cache = entryCreationKeyState.entryCreationKeyLevelCache")

    assert normalize_idx < unknown_idx < cache_idx
    assert "return 0, \"ignored: active activity unknown\", false" in resolver_body[unknown_idx:cache_idx]
    assert "entryCreationKeyState.ResolveCachedEntryCreationKeystoneLevel(activityID, questID)" in getter_body


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
    assert "_SetupLFGEntryCreationKeyCapture = function()" in source
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
        creation_body.index("pendingEntryCreationKeyLevelCache = {")
    )


def test_lfg_key_capture_setup_is_independent_from_default_playstyle_internal():
    source = _lua_source()
    key_capture_body = _slice_between(
        source,
        "_SetupLFGEntryCreationKeyCapture = function()",
        "_SetupLFGDefaultPlaystyle = function()",
    )
    playstyle_body = _slice_between(
        source,
        "_SetupLFGDefaultPlaystyle = function()",
        "local EVENT_HANDLERS = {",
    )

    assert "LFGListEntryCreation_OnPlayStyleSelectedInternal" not in key_capture_body
    assert "_HookEntryCreationKeyCapture(panel)" in key_capture_body
    assert "LFGListEntryCreation_OnPlayStyleSelectedInternal" in playstyle_body
    assert "_HookEntryCreationKeyCapture" not in playstyle_body


def test_status_reports_key_capture_hooks_and_cache_decision_separately():
    source = _lua_source()
    status_body = _slice_between(
        source,
        'elseif msg == "status" then',
        'elseif msg == "taintcheck" then',
    )
    diagnostics_body = _slice_between(
        source,
        "entryCreationKeyState.PrintDiagnostics = function()",
        "entryCreationKeyState.ReconcileEntryCreationKeyCache = function(listingContext)",
    )

    assert "entryCreationKeyState.PrintDiagnostics()" in status_body
    assert "entry key capture hooks:" in diagnostics_body
    assert "default playstyle hooks:" in status_body
    assert "pendingEntryCreationCache.keyLevel" in diagnostics_body
    assert "publishedEntryCreationCache.keyLevel" in diagnostics_body
    assert "listing cache decision:" in diagnostics_body
    assert "entryCreationKeyState.PeekCachedEntryCreationKeystoneLevel(" in status_body
    assert "cleanActivityID, cleanQuestID" in status_body
    assert "cachedLevel and cachedLevel(cleanActivityID, cleanQuestID)" not in status_body


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
