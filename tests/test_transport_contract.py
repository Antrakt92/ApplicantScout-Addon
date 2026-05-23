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
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    payload_idx = body.index("local payload = BuildPayload(entry, applicantIDs, terminalClear)")
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
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    suppression_idx = screenshot_body.index("not force and _qrSuppressedByInteraction")
    payload_idx = screenshot_body.index("local payload = BuildPayload(entry, applicantIDs, terminalClear)")
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


def test_qr_library_resolution_is_nil_safe_before_missing_lib_diagnostic():
    source = _lua_source()
    qr_init_idx = source.index("local _qrencode =")
    build_idx = source.index("local function BuildQRMatrix(payload)")
    init_line = source[qr_init_idx : source.index("\n", qr_init_idx)]

    assert qr_init_idx < build_idx
    assert "_addonNS.QR and _addonNS.QR.qrcode" in init_line
    assert "_addonNS and" not in init_line


def test_party_roster_starts_transport_without_lfg_listing():
    source = _lua_source()
    transition_body = _slice_between(
        source,
        "CheckSessionTransition = function()",
        "-- Single transition logger",
    )
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
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


def test_non_force_screenshot_waits_for_roster_inspect_batch_before_payload():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    batch_idx = screenshot_body.index(
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()"
    )
    applicant_idx = screenshot_body.index("local applicantIDs = {}")
    empty_guard_idx = screenshot_body.index("#applicantIDs == 0", applicant_idx)
    force_guard_idx = screenshot_body.rindex("not force", 0, batch_idx)
    pending_idx = screenshot_body.index("pendingShotDirty = true", batch_idx)
    entry_idx = screenshot_body.index("local entry = nil")
    payload_idx = screenshot_body.index("local payload = BuildPayload")

    assert entry_idx < applicant_idx < empty_guard_idx < batch_idx
    assert force_guard_idx < batch_idx
    assert batch_idx < pending_idx < payload_idx


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


def test_roster_name_falls_back_to_visible_unit_name_when_full_name_is_missing():
    source = _lua_source()
    name_body = _slice_between(
        source,
        "local function _UnitFullNameForTransport(unit)",
        "local function _UnitClassIDForRoster(unit)",
    )

    full_name_idx = name_body.index("pcall(UnitFullName, unit)")
    fallback_idx = name_body.index("pcall(GetUnitName, unit, true)")
    safe_fallback_idx = name_body.index("SafeStr(unitName, \"\")", fallback_idx)

    assert full_name_idx < fallback_idx < safe_fallback_idx
    assert "if name == \"\" and GetUnitName then" in name_body
    assert 'name:find("-", 1, true)' in name_body


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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )

    assert "string.char(0x06)" in payload_body
    assert "BuildRosterPayloadRows(" in payload_body
    applicants_idx = payload_body.index("for _, chunk in ipairs(memberOut) do")
    roster_idx = payload_body.index("table.insert(out, _Uint16BE(rosterCount))")
    assert applicants_idx < roster_idx
    assert "for _, chunk in ipairs(rosterOut) do" in payload_body


def test_full_party_quiet_signature_requires_empty_resolved_non_raid_roster():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    assert "entryCreationKeyState.lastPayloadQuietFullPartySignature = nil" in payload_body
    assert "rosterQuietSignature, rosterQuietHasUnknownSpec, rosterQuietInRaid" in payload_body
    assert "cleanEntry and #validApps == 0" in payload_body
    assert "rosterCount == 5" in payload_body
    assert "not rosterQuietInRaid" in payload_body
    assert "not rosterQuietHasUnknownSpec" in payload_body
    assert "entryCreationKeyState.lastPayloadQuietFullPartySignature =" in payload_body
    assert "local rosterQuietOut = {}" in roster_body
    assert "rosterQuietHasUnknownSpec = true" in roster_body
    assert "row.name" in roster_body
    assert "row.classID" in roster_body
    assert "row.specID" in roster_body
    assert "row.role" in roster_body
    assert "table.concat(rosterQuietOut)" in roster_body


def test_repeat_full_party_quiet_snapshot_is_suppressed_before_qr_paint():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    hash_idx = screenshot_body.index("local h = HashSnapshot(payload)")
    quiet_idx = screenshot_body.index(
        "local quietSignature = entryCreationKeyState.lastPayloadQuietFullPartySignature"
    )
    throttle_idx = screenshot_body.index("if not force and now - lastShotTime < SHOT_THROTTLE_S")
    matrix_idx = screenshot_body.index("local matrix = BuildQRMatrix(payload)")
    quiet_block = screenshot_body[
        quiet_idx : screenshot_body.index("\n    -- Encode payload", quiet_idx)
    ]

    assert hash_idx < throttle_idx < quiet_idx < matrix_idx
    assert "entryCreationKeyState.lastQuietFullPartySignature == quietSignature" in quiet_block
    assert "lastSnapshotHash = h" in quiet_block
    assert "pendingShotDirty = false" in quiet_block
    assert "return" in quiet_block
    assert "entryCreationKeyState.lastQuietFullPartySignature = nil" in quiet_block


def test_quiet_signature_is_committed_only_after_successful_qr_paint():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    quiet_idx = screenshot_body.index(
        "local quietSignature = entryCreationKeyState.lastPayloadQuietFullPartySignature"
    )
    matrix_idx = screenshot_body.index("local matrix = BuildQRMatrix(payload)")
    paint_failure_idx = screenshot_body.index("if not PaintQR(matrix) then")
    lease_idx = screenshot_body.index(
        "local forceVisibleShotGen, forceVisibleShotDelay = _AcquireQRShotLease()"
    )
    commit_idx = screenshot_body.index(
        "entryCreationKeyState.lastQuietFullPartySignature = quietSignature",
        paint_failure_idx,
    )
    pre_paint_quiet_block = screenshot_body[quiet_idx:matrix_idx]

    assert quiet_idx < matrix_idx < paint_failure_idx < commit_idx < lease_idx
    assert "entryCreationKeyState.lastQuietFullPartySignature == quietSignature" in (
        pre_paint_quiet_block
    )
    assert (
        "entryCreationKeyState.lastQuietFullPartySignature = quietSignature"
        not in pre_paint_quiet_block
    )


def test_quiet_full_party_signature_uses_collision_safe_encoding():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    assert 'table.concat({' not in payload_body
    assert 'string.format(\n            "%d:%d:%s' not in roster_body
    assert "listingQuietOut" in payload_body
    assert "_PackLenStr(listingQuietOut, dungeonName)" in payload_body
    assert "rosterQuietOut" in roster_body
    assert "_PackLenStr(rosterQuietOut, row.name)" in roster_body


def test_quiet_full_party_signature_covers_companion_visible_roster_fields():
    source = _lua_source()
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )
    quiet_idx = roster_body.index("local rosterQuietOut = {}")

    expected_fields = [
        "row.unitIndex",
        "row.flags",
        "row.subgroup",
        "row.classID",
        "row.specID",
        "row.ilvl",
        "rioSummary.currentScore",
        "rioSummary.mainScore",
        "rioSummary.hasProfile",
        "rioSummary.bestKey",
        "rioSummary.bestDungeonKey",
        "rioSummary.timedAtOrAbove",
        "rioSummary.timedAtOrAboveMinus1",
        "rioSummary.timedAtOrAboveMinus2",
        "rioSummary.completedAtOrAboveMinus1",
        "rioSummary.dungeonCount",
        "row.role",
        "row.name",
    ]

    for field in expected_fields:
        assert field in roster_body[quiet_idx:]
    assert roster_body.count("_GetRaiderIOMPlusSummary(") == 1


def test_terminal_clear_is_only_passed_by_end_session():
    source = _lua_source()
    end_body = _slice_between(
        source,
        "EndSession = function()",
        "local function _HasGroupRosterForTransport()",
    )
    shotnow_body = _slice_between(
        source,
        'elseif msg == "shotnow" then',
        'elseif msg == "qrvisible" then',
    )

    assert "MaybeTriggerScreenshot(true, nil, true)" in end_body
    assert "MaybeTriggerScreenshot(true, entry, true)" not in shotnow_body
    assert "MaybeTriggerScreenshot(true, entry)" in shotnow_body


def test_end_session_retries_terminal_clear_in_same_session_generation():
    source = _lua_source()
    end_body = _slice_between(
        source,
        "EndSession = function()",
        "local function _HasGroupRosterForTransport()",
    )

    first_clear_idx = end_body.index("MaybeTriggerScreenshot(true, nil, true)")
    retry_gen_idx = end_body.index("local clearRetryGen = sessionGen")
    retry_after_idx = end_body.index("C_Timer.After(QR_RENDER_SETTLE_S * 2, function()")
    guard_idx = end_body.index("if sessionGen == clearRetryGen and not isSessionActive then")
    retry_clear_idx = end_body.index(
        "MaybeTriggerScreenshot(true, nil, true)",
        first_clear_idx + 1,
    )
    hide_idx = end_body.index("local genAtSchedule = sessionGen")

    assert first_clear_idx < retry_gen_idx < retry_after_idx < guard_idx < retry_clear_idx
    assert retry_clear_idx < hide_idx


def test_applicant_payload_skips_secret_placeholder_names():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )

    assert 'local memberName = SafeStr(name, "")' in payload_body
    assert 'if memberName ~= "" and memberName ~= "?" then' in payload_body


def test_terminal_clear_skips_roster_block_but_normal_roster_survives():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )

    assert "local payload = BuildPayload(entry, applicantIDs, terminalClear)" in screenshot_body
    assert "local rosterOut, rosterCount = {}, 0" in payload_body
    assert "local rosterIncomplete = false" in payload_body
    assert "if not terminalClear then" in payload_body
    roster_call_idx = payload_body.index("BuildRosterPayloadRows(")
    terminal_guard_idx = payload_body.index("if not terminalClear then")
    count_idx = payload_body.index("table.insert(out, _Uint16BE(rosterCount))")
    assert terminal_guard_idx < roster_call_idx < count_idx
    assert "for _, chunk in ipairs(rosterOut) do" in payload_body


def test_roster_payload_marks_group_snapshot_incomplete_when_expected_rows_are_missing():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    assert "entryCreationKeyState.lastPayloadRosterIncomplete = false" in payload_body
    assert "local expectedRosterCount = 0" in roster_body
    assert "expectedRosterCount = groupCount" in roster_body
    assert "local rosterIncomplete = emittedCount < expectedRosterCount" in roster_body
    assert "rosterQuietHasUnknownSpec, inRaid, rosterIncomplete" in roster_body
    assert "entryCreationKeyState.lastPayloadRosterIncomplete = rosterIncomplete" in (
        payload_body
    )


def test_party_roster_with_unknown_spec_stays_incomplete_until_clear_data():
    source = _lua_source()
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    unknown_spec_idx = roster_body.index("if row.specID <= 0 then")
    incomplete_idx = roster_body.index("local rosterIncomplete =")
    return_idx = roster_body.index("return rosterOut, emittedCount", incomplete_idx)

    assert unknown_spec_idx < incomplete_idx < return_idx
    assert "or (not inRaid and rosterQuietHasUnknownSpec)" in roster_body[
        incomplete_idx:return_idx
    ]


def test_incomplete_roster_payload_retries_even_when_hash_is_unchanged():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    same_hash_idx = screenshot_body.index("if not force and h == lastSnapshotHash then")
    incomplete_idx = screenshot_body.index(
        "entryCreationKeyState.lastPayloadRosterIncomplete",
        same_hash_idx,
    )
    retry_idx = screenshot_body.index(
        "entryCreationKeyState.ScheduleRosterLoadRetry(SHOT_THROTTLE_S)",
        incomplete_idx,
    )
    clear_pending_idx = screenshot_body.index("pendingShotDirty = false", retry_idx)
    fallback_pending_idx = screenshot_body.index("pendingShotDirty = true", retry_idx)
    return_idx = screenshot_body.index("return", retry_idx)
    throttle_idx = screenshot_body.index("local now = GetTime()")

    assert same_hash_idx < incomplete_idx < retry_idx < clear_pending_idx < fallback_pending_idx
    assert fallback_pending_idx < return_idx
    assert return_idx < throttle_idx


def test_incomplete_roster_payload_schedules_retry_after_successful_qr_paint():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    paint_success_idx = screenshot_body.index(
        "local forceVisibleShotGen, forceVisibleShotDelay = _AcquireQRShotLease()"
    )
    clear_pending_idx = screenshot_body.index("pendingShotDirty = false", paint_success_idx)
    incomplete_idx = screenshot_body.index(
        "entryCreationKeyState.lastPayloadRosterIncomplete",
        clear_pending_idx,
    )
    retry_idx = screenshot_body.index(
        "entryCreationKeyState.ScheduleRosterLoadRetry(SHOT_THROTTLE_S)",
        incomplete_idx,
    )
    retry_clear_pending_idx = screenshot_body.index("pendingShotDirty = false", retry_idx)
    fallback_pending_idx = screenshot_body.index("pendingShotDirty = true", retry_idx)
    screenshot_schedule_idx = screenshot_body.index(
        "C_Timer.After(forceVisibleShotDelay, function()",
        retry_idx,
    )

    assert paint_success_idx < clear_pending_idx < incomplete_idx < retry_idx
    assert retry_idx < retry_clear_pending_idx < fallback_pending_idx
    assert fallback_pending_idx < screenshot_schedule_idx


def test_roster_load_retry_callback_requires_current_token_and_session():
    source = _lua_source()
    retry_body = _slice_between(
        source,
        "entryCreationKeyState.ScheduleRosterLoadRetry = function(delay)",
        "entryCreationKeyState.RosterUnitHasResolvedSpec = function(unit, guid)",
    )

    token_idx = retry_body.index("local retryToken = entryCreationKeyState.rosterLoadRetryToken")
    callback_idx = retry_body.index("C_Timer.After(delay, function()")
    token_guard_idx = retry_body.index(
        "retryToken ~= entryCreationKeyState.rosterLoadRetryToken",
        callback_idx,
    )
    session_guard_idx = retry_body.index("retrySessionGen ~= sessionGen", token_guard_idx)
    enabled_guard_idx = retry_body.index(
        "ApplicantScoutDB and ApplicantScoutDB.enabled",
        session_guard_idx,
    )
    active_guard_idx = retry_body.index("if not isSessionActive then return end")
    pending_idx = retry_body.index("pendingShotDirty = true", active_guard_idx)
    dirty_idx = retry_body.index('MarkDirty("rosterload")', pending_idx)

    assert token_idx < callback_idx < token_guard_idx < session_guard_idx
    assert session_guard_idx < enabled_guard_idx < active_guard_idx < pending_idx < dirty_idx


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


def test_roster_payload_rows_pack_current_score_separately_from_main_score():
    source = _lua_source()
    summary_body = _slice_between(
        source,
        "local function _GetRaiderIOMPlusSummary(memberName, listingActivityID, targetKey)",
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
    )
    roster_body = _slice_between(
        source,
        "local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)",
        "-- CRC32 IEEE-802.3",
    )

    current_idx = roster_body.index("_Uint16BE(rioSummary.currentScore)")
    main_idx = roster_body.index("_Uint16BE(rioSummary.mainScore)")
    assert current_idx < main_idx
    assert roster_body.count("_Uint16BE(rioSummary.mainScore)") == 1
    assert "keystoneProfile.mplusCurrent" in summary_body
    assert "keystoneProfile.currentScore" in summary_body
    assert "keystoneProfile.mplusMainCurrent" in summary_body
    assert "keystoneProfile.mainCurrentScore" in summary_body


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


def test_auto_hi_defaults_to_empty_and_normalizes_saved_message():
    source = _lua_source()
    defaults_body = _slice_between(
        source,
        "local DB_DEFAULTS = {",
        "-- Session lifecycle.",
    )
    init_body = _slice_between(
        source,
        "InitDB = function()",
        "APSPrint = function(msg)",
    )

    assert 'autoHiMessage = "",' in defaults_body
    assert "autoHiGreetNewPartyMembers = false," in defaults_body
    assert "ApplicantScoutDB.autoHiMessage =" in init_body
    assert "entryCreationKeyState.NormalizeAutoHiMessage(" in init_body


def test_auto_hi_settings_panel_persists_user_message_from_edit_box():
    source = _lua_source()
    settings_body = _slice_between(
        source,
        "-- Settings panel: pinned above PVEFrame",
        "-- slash commands",
    )

    assert "ApplicantScoutSettingsAutoHiEditBox" in settings_body
    assert '"InputBoxTemplate"' in settings_body
    assert "autoHiDivider:SetColorTexture(1, 1, 1, 0.14)" in settings_body
    assert 'autoHiLabel:SetText("Auto Hi on invite")' in settings_body
    assert 'autoHiHint:SetText("blank = off, sends after 5s")' in settings_body
    assert 'autoHiEditBox:SetScript("OnEnterPressed"' in settings_body
    assert 'autoHiEditBox:SetScript("OnEditFocusLost"' in settings_body
    assert "entryCreationKeyState.SetAutoHiMessage(self:GetText(), true)" in settings_body
    assert "entryCreationKeyState.SyncAutoHiEditBox()" in settings_body
    assert "ApplicantScoutSettingsAutoHiNewPartyMembersCheckbox" in settings_body
    assert '_StyleCheckboxLabel(autoHiNewPartyMembersCheckbox, "Greet new party members")' in settings_body
    assert "ApplicantScoutDB.autoHiGreetNewPartyMembers" in settings_body
    assert "Disabled in raids." in settings_body


def test_auto_hi_group_transition_schedules_one_delayed_clean_chat_send():
    source = _lua_source()
    auto_hi_body = _slice_between(
        source,
        "entryCreationKeyState.IsGroupedForAutoHi = function()",
        "CheckSessionTransition = function()",
    )
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    assert "AUTO_HI_DELAY_S = 5" in source
    assert "autoHiWasInGroup" in auto_hi_body
    assert "entryCreationKeyState.autoHiGroupGen + 1" in auto_hi_body
    assert "C_Timer.After(entryCreationKeyState.AUTO_HI_DELAY_S, function()" in auto_hi_body
    assert "if groupGen ~= entryCreationKeyState.autoHiGroupGen" in auto_hi_body
    assert "entryCreationKeyState.SendAutoHiChatMessage(message)" in auto_hi_body
    assert "if IsChatMessagingLockdown() then return false end" in auto_hi_body
    assert "GROUP_ROSTER_UPDATE              = function()" in events_body
    assert "entryCreationKeyState.ScheduleAutoHiIfGroupJoined()" in events_body
    assert "GROUP_LEFT                       = function()" in events_body


def test_auto_hi_baselines_existing_group_without_greeting_on_reload():
    source = _lua_source()
    auto_hi_body = _slice_between(
        source,
        "entryCreationKeyState.SyncAutoHiInitialGroupState = function()",
        "entryCreationKeyState.ScheduleAutoHiIfGroupJoined = function()",
    )
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    assert "autoHiGroupStateKnown" in auto_hi_body
    assert "local isGrouped = entryCreationKeyState.IsGroupedForAutoHi()" in auto_hi_body
    assert "entryCreationKeyState.autoHiWasInGroup = isGrouped" in auto_hi_body
    assert "entryCreationKeyState.SyncAutoHiInitialGroupState()" in events_body
    assert "PLAYER_ENTERING_WORLD" in events_body


def test_auto_hi_new_party_members_is_opt_in_party_only_and_guid_tracked():
    source = _lua_source()
    auto_hi_body = _slice_between(
        source,
        "entryCreationKeyState.IsGroupedForAutoHi = function()",
        "CheckSessionTransition = function()",
    )
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    assert "entryCreationKeyState.IsPartyForAutoHiNewMembers = function()" in auto_hi_body
    assert "if IsInRaid and IsInRaid() then return false end" in auto_hi_body
    assert "entryCreationKeyState.CollectAutoHiPartyMemberGUIDs = function()" in auto_hi_body
    assert "for i = 1, 4 do" in auto_hi_body
    assert 'UnitGUID("party" .. i)' in auto_hi_body
    assert "entryCreationKeyState.autoHiKnownPartyGUIDs" in auto_hi_body
    assert "entryCreationKeyState.PrimeAutoHiPartyMembers()" in auto_hi_body
    assert "entryCreationKeyState.ScheduleAutoHiForNewPartyMembers = function()" in auto_hi_body
    assert "ApplicantScoutDB.autoHiGreetNewPartyMembers" in auto_hi_body
    assert "entryCreationKeyState.autoHiNewPartyMemberGen + 1" in auto_hi_body
    assert "if groupGen ~= entryCreationKeyState.autoHiNewPartyMemberGen" in auto_hi_body
    assert "entryCreationKeyState.ScheduleAutoHiForNewPartyMembers()" in events_body


def test_inspect_ready_batches_followup_roster_inspects_before_dirty():
    source = _lua_source()
    request_body = _slice_between(
        source,
        "local function _MaybeRequestRosterInspect(unit, guid)",
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
    )
    batch_body = _slice_between(
        source,
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
        "local function _OnRosterInspectReady(guid)",
    )
    inspect_body = _slice_between(
        source,
        "local function _OnRosterInspectReady(guid)",
        "local function _UnitSpecIDForRoster(unit)",
    )

    assert "return true" in request_body
    assert "return false" in request_body
    assert "entryCreationKeyState.FlushOrContinueRosterInspectBatch" in batch_body
    assert "ROSTER_INSPECT_TIMEOUT_S - (now - rosterInspectLastRequestTime)" in batch_body
    assert "rosterInspectPendingGUID = nil" in batch_body
    assert "entryCreationKeyState.rosterInspectBatchDirtyPending = true" in inspect_body
    continue_idx = inspect_body.index(
        "entryCreationKeyState.FlushOrContinueRosterInspectBatch()"
    )
    dirty_idx = inspect_body.index('MarkDirty("inspect")')
    assert continue_idx < dirty_idx


def test_roster_inspect_batch_skips_timed_out_guid_before_requesting_next():
    source = _lua_source()
    batch_body = _slice_between(
        source,
        "entryCreationKeyState.FlushOrContinueRosterInspectBatch = function()",
        "local function _OnRosterInspectReady(guid)",
    )

    timeout_idx = batch_body.index("local timedOutGUID = rosterInspectPendingGUID")
    skipped_set_idx = batch_body.index(
        "entryCreationKeyState.rosterInspectBatchSkippedGUIDs[timedOutGUID] = true"
    )
    loop_idx = batch_body.index("_ForEachRosterUnit(function(unit)")
    skipped_guard_idx = batch_body.index(
        "entryCreationKeyState.rosterInspectBatchSkippedGUIDs[guid]",
        loop_idx,
    )
    request_idx = batch_body.index("_MaybeRequestRosterInspect(unit, guid)", loop_idx)
    clear_idx = batch_body.index(
        "entryCreationKeyState.rosterInspectBatchSkippedGUIDs = nil",
        request_idx,
    )

    assert timeout_idx < skipped_set_idx < loop_idx < skipped_guard_idx < request_idx
    assert request_idx < clear_idx


def test_pending_roster_inspect_does_not_reissue_same_guid_before_timeout():
    source = _lua_source()
    request_body = _slice_between(
        source,
        "local function _MaybeRequestRosterInspect(unit, guid)",
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
    )

    now_idx = request_body.index("local now = GetTime and GetTime() or 0")
    same_guid_idx = request_body.index("rosterInspectPendingGUID == guid")
    timeout_idx = request_body.index("ROSTER_INSPECT_TIMEOUT_S", same_guid_idx)
    throttle_idx = request_body.index("ROSTER_INSPECT_THROTTLE_S")
    notify_idx = request_body.index("pcall(NotifyInspect, unit)")

    assert now_idx < same_guid_idx < timeout_idx < throttle_idx < notify_idx


def test_session_transitions_clear_roster_inspect_pending_state():
    source = _lua_source()
    start_body = _slice_between(source, "StartSession = function()", "EndSession = function()")
    end_body = _slice_between(
        source,
        "EndSession = function()",
        "local function _HasGroupRosterForTransport()",
    )

    for body in (start_body, end_body):
        assert "entryCreationKeyState.ClearRosterInspectBatchState()" in body


def test_roster_inspect_retry_scheduler_coalesces_duplicate_deadlines():
    source = _lua_source()
    retry_body = _slice_between(
        source,
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
        "entryCreationKeyState.RosterUnitHasResolvedSpec = function(unit, guid)",
    )

    assert "rosterInspectBatchRetryDeadline" in retry_body
    assert "rosterInspectBatchRetryToken" in retry_body
    assert "existingDeadline <= due" in retry_body
    assert "return true" in retry_body[retry_body.index("existingDeadline <= due") :]


def test_roster_inspect_retry_callback_requires_current_token():
    source = _lua_source()
    retry_body = _slice_between(
        source,
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
        "entryCreationKeyState.RosterUnitHasResolvedSpec = function(unit, guid)",
    )

    token_idx = retry_body.index("local retryToken = entryCreationKeyState.rosterInspectBatchRetryToken")
    callback_idx = retry_body.index("C_Timer.After(delay, function()")
    guard_idx = retry_body.index(
        "retryToken ~= entryCreationKeyState.rosterInspectBatchRetryToken",
        callback_idx,
    )
    flush_idx = retry_body.index("entryCreationKeyState.FlushOrContinueRosterInspectBatch()", guard_idx)

    assert token_idx < callback_idx < guard_idx < flush_idx
    assert "retrySessionGen ~= sessionGen" in retry_body[callback_idx:flush_idx]
    assert "ApplicantScoutDB and ApplicantScoutDB.enabled" in retry_body[callback_idx:flush_idx]


def test_start_end_session_invalidate_roster_inspect_retry_token():
    source = _lua_source()
    start_body = _slice_between(source, "StartSession = function()", "EndSession = function()")
    end_body = _slice_between(
        source,
        "EndSession = function()",
        "local function _HasGroupRosterForTransport()",
    )
    clear_body = _slice_between(
        source,
        "entryCreationKeyState.ClearRosterInspectBatchState = function()",
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
    )

    assert "entryCreationKeyState.ClearRosterInspectBatchState()" in start_body
    assert "entryCreationKeyState.ClearRosterInspectBatchState()" in end_body
    assert "rosterInspectBatchRetryToken" in clear_body
    assert "rosterInspectBatchRetryDeadline = nil" in clear_body
    assert "rosterInspectPendingGUID = nil" in clear_body


def test_combat_block_keeps_batch_pending_until_player_regen_enabled():
    source = _lua_source()
    request_body = _slice_between(
        source,
        "local function _MaybeRequestRosterInspect(unit, guid)",
        "entryCreationKeyState.ClearRosterInspectBatchState = function()",
    )
    batch_body = _slice_between(
        source,
        "entryCreationKeyState.FlushOrContinueRosterInspectBatch = function()",
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot = function()",
    )

    assert 'return false, "combat"' in request_body
    assert 'requestReason == "combat"' in batch_body
    assert "entryCreationKeyState.rosterInspectBatchCombatDeferred = true" in batch_body
    assert "entryCreationKeyState.rosterInspectBatchDirtyPending = false" not in (
        batch_body[
            batch_body.index('requestReason == "combat"') :
            batch_body.index("if requested then")
        ]
    )


def test_combat_deferred_roster_preflight_allows_partial_snapshot():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    preflight_idx = screenshot_body.index(
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()"
    )
    combat_deferred_idx = screenshot_body.index(
        "entryCreationKeyState.rosterInspectBatchCombatDeferred",
        preflight_idx,
    )
    pending_idx = screenshot_body.index("pendingShotDirty = true", combat_deferred_idx)
    return_idx = screenshot_body.index("return", pending_idx)
    payload_idx = screenshot_body.index("local payload = BuildPayload", return_idx)

    assert preflight_idx < combat_deferred_idx < pending_idx < return_idx < payload_idx
    assert "not entryCreationKeyState.rosterInspectBatchCombatDeferred" in (
        screenshot_body[preflight_idx:pending_idx]
    )


def test_player_regen_enabled_flushes_roster_inspect_batch():
    source = _lua_source()
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )
    regen_body = _slice_between(
        events_body,
        "PLAYER_REGEN_ENABLED",
        "INSPECT_READY",
    )

    assert "entryCreationKeyState.rosterInspectBatchCombatDeferred" in regen_body
    assert "entryCreationKeyState.FlushOrContinueRosterInspectBatch()" in regen_body
    assert 'MarkDirty("inspect")' in regen_body


def test_initial_unknown_roster_spec_preflight_defers_only_when_inspect_starts():
    source = _lua_source()
    ensure_body = _slice_between(
        source,
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot = function()",
        "local function _OnRosterInspectReady(guid)",
    )
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    ensure_idx = screenshot_body.index("entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()")
    payload_idx = screenshot_body.index("local payload = BuildPayload(entry, applicantIDs, terminalClear)")

    assert "_ForEachRosterUnit(function(unit)" in ensure_body
    assert "entryCreationKeyState.RosterUnitHasResolvedSpec(unit, guid)" in ensure_body
    assert "_GetRaiderIOMPlusSummary(" not in ensure_body
    assert "BuildRosterPayloadRows(" not in ensure_body
    assert ensure_idx < payload_idx


def test_initial_roster_spec_preflight_does_not_hold_raid_snapshots():
    source = _lua_source()
    ensure_body = _slice_between(
        source,
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot = function()",
        "local function _OnRosterInspectReady(guid)",
    )

    group_count_idx = ensure_body.index("local groupCount = math.floor")
    max_party_idx = ensure_body.index("groupCount > 5")
    raid_idx = ensure_body.index("IsInRaid and IsInRaid()")
    seed_idx = ensure_body.index("local seeded = false")

    assert group_count_idx < max_party_idx < raid_idx < seed_idx


def test_initial_roster_spec_preflight_does_not_hold_applicant_snapshots():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    applicant_idx = screenshot_body.index("local applicantIDs = {}")
    applicant_fetch_idx = screenshot_body.index("C_LFGList.GetApplicants()", applicant_idx)
    empty_guard_idx = screenshot_body.index("#applicantIDs == 0", applicant_fetch_idx)
    preflight_idx = screenshot_body.index(
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()",
        empty_guard_idx,
    )
    payload_idx = screenshot_body.index("local payload = BuildPayload", preflight_idx)

    assert applicant_idx < applicant_fetch_idx < empty_guard_idx < preflight_idx < payload_idx


def test_empty_applicant_clear_after_emitted_applicants_bypasses_roster_preflight():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    applicant_idx = screenshot_body.index("local applicantIDs = {}")
    applicant_fetch_idx = screenshot_body.index("C_LFGList.GetApplicants()", applicant_idx)
    empty_guard_idx = screenshot_body.index("#applicantIDs == 0", applicant_fetch_idx)
    prior_applicant_guard_idx = screenshot_body.index(
        "lastEmittedApplicantCount == 0",
        empty_guard_idx,
    )
    preflight_idx = screenshot_body.index(
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()",
        prior_applicant_guard_idx,
    )
    payload_idx = screenshot_body.index("local payload = BuildPayload", preflight_idx)

    assert (
        applicant_idx
        < applicant_fetch_idx
        < empty_guard_idx
        < prior_applicant_guard_idx
        < preflight_idx
        < payload_idx
    )


def test_successful_snapshot_commits_emitted_applicant_count_for_clear_priority():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )

    emit_count_idx = payload_body.index("local emittedCount = 0")
    payload_count_idx = payload_body.index(
        "entryCreationKeyState.lastPayloadApplicantCount = emittedCount"
    )
    paint_idx = screenshot_body.index("if not PaintQR(matrix) then")
    commit_idx = screenshot_body.index(
        "entryCreationKeyState.lastEmittedApplicantCount =",
        paint_idx,
    )
    committed_value_idx = screenshot_body.index(
        "entryCreationKeyState.lastPayloadApplicantCount",
        commit_idx,
    )
    shot_idx = screenshot_body.index("lastShotTime = now", commit_idx)

    assert emit_count_idx < payload_count_idx
    assert paint_idx < commit_idx < committed_value_idx < shot_idx


def test_roster_batch_clears_pending_guid_when_unit_leaves():
    source = _lua_source()
    batch_body = _slice_between(
        source,
        "entryCreationKeyState.FlushOrContinueRosterInspectBatch = function()",
        "entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot = function()",
    )
    inspect_body = _slice_between(
        source,
        "local function _OnRosterInspectReady(guid)",
        "local function _UnitSpecIDForRoster(unit)",
    )

    missing_idx = batch_body.index("not _FindRosterUnitByGUID(rosterInspectPendingGUID)")
    skip_idx = batch_body.index("rosterInspectBatchSkippedGUIDs[missingGUID] = true", missing_idx)
    timeout_idx = batch_body.index("local timeoutLeft = ROSTER_INSPECT_TIMEOUT_S", missing_idx)

    assert missing_idx < skip_idx < timeout_idx
    assert "if rosterInspectPendingGUID == guid then" in inspect_body
    assert "rosterInspectPendingGUID = nil" in inspect_body


def test_reset_invalidates_roster_inspect_batch_retry_without_clearing_known_specs():
    source = _lua_source()
    reset_body = _slice_between(
        source,
        'elseif msg == "reset" then',
        'elseif msg == "shotnow" then',
    )

    clear_idx = reset_body.index("entryCreationKeyState.ClearRosterInspectBatchState()")
    dirty_idx = reset_body.index("scanDirty = true")

    assert clear_idx < dirty_idx
    assert "rosterInspectSpecByGUID = {}" not in reset_body
    assert "rosterInspectBatchRetryToken" not in reset_body


def test_status_reports_roster_inspect_batch_diagnostics_without_raw_ids():
    source = _lua_source()
    status_body = _slice_between(
        source,
        'elseif msg == "status" then',
        'elseif msg == "taintcheck" then',
    )
    diagnostics_body = _slice_between(
        source,
        "entryCreationKeyState.PrintRosterInspectBatchDiagnostics = function()",
        "entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)",
    )

    assert "entryCreationKeyState.PrintRosterInspectBatchDiagnostics()" in status_body
    assert "roster inspect batch:" in diagnostics_body
    assert "batch pending:" in diagnostics_body
    assert "pending inspect:" in diagnostics_body
    assert "retry scheduled:" in diagnostics_body
    assert "combat deferred:" in diagnostics_body
    assert "last block reason:" in diagnostics_body
    assert "skipped count:" in diagnostics_body
    assert "rosterInspectPendingGUID)" not in diagnostics_body
    assert "lastQuietFullPartySignature)" not in diagnostics_body


def test_terminal_clear_force_path_bypasses_roster_inspect_batch_gate():
    source = _lua_source()
    screenshot_body = _slice_between(
        source,
        "MaybeTriggerScreenshot = function(force, entryHint, terminalClear)",
        "-- LFG entry creation",
    )
    end_body = _slice_between(
        source,
        "EndSession = function()",
        "local function _HasGroupRosterForTransport()",
    )

    batch_idx = screenshot_body.index("entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()")
    force_guard_idx = screenshot_body.rindex("not force", 0, batch_idx)

    assert "MaybeTriggerScreenshot(true, nil, true)" in end_body
    assert force_guard_idx < batch_idx


def test_reset_clears_quiet_full_party_signature_before_queuing_resync():
    source = _lua_source()
    reset_body = _slice_between(
        source,
        'elseif msg == "reset" then',
        'elseif msg == "shotnow" then',
    )

    quiet_idx = reset_body.index("entryCreationKeyState.lastQuietFullPartySignature = nil")
    payload_quiet_idx = reset_body.index(
        "entryCreationKeyState.lastPayloadQuietFullPartySignature = nil"
    )
    dirty_idx = reset_body.index("scanDirty = true")

    assert quiet_idx < dirty_idx
    assert payload_quiet_idx < dirty_idx


def test_specialization_changed_invalidates_changed_unit_guid_before_dirty():
    source = _lua_source()
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )
    handler_body = _slice_between(
        events_body,
        "PLAYER_SPECIALIZATION_CHANGED      = function(_, unit)",
        "INSPECT_READY",
    )

    invalidate_idx = handler_body.index("_InvalidateRosterSpecCacheForUnit(unit)")
    dirty_idx = handler_body.index('MarkDirty("spec")')

    assert invalidate_idx < dirty_idx


def test_roster_spec_cache_invalidation_clears_pending_inspect_for_changed_guid():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _InvalidateRosterSpecCacheForUnit(unit)",
        "local function _MaybeRequestRosterInspect(unit, guid)",
    )

    assert "local guid = _UnitGUIDForRoster(unit)" in helper_body
    assert "rosterInspectSpecByGUID[guid] = nil" in helper_body
    assert "if rosterInspectPendingGUID == guid then" in helper_body
    assert "rosterInspectPendingGUID = nil" in helper_body
    assert "rosterInspectSpecByGUID = {}" in helper_body


def test_roster_dirty_events_are_registered():
    source = _lua_source()
    events_body = _slice_between(
        source,
        "local EVENT_HANDLERS = {",
        "-- Bind every interaction event",
    )

    roster_idx = events_body.index("GROUP_ROSTER_UPDATE              = function()")
    roster_dirty_idx = events_body.index('MarkDirty("roster")', roster_idx)
    auto_hi_idx = events_body.index(
        "entryCreationKeyState.ScheduleAutoHiIfGroupJoined()", roster_idx
    )
    assert roster_dirty_idx < auto_hi_idx
    assert 'PLAYER_SPECIALIZATION_CHANGED      = function(_, unit)' in events_body
    assert "_InvalidateRosterSpecCacheForUnit(unit)" in events_body
    assert 'MarkDirty("spec")' in events_body


def test_listing_key_level_uses_owned_keystone_only_after_listing_match_guard():
    source = _lua_source()
    helper_body = _slice_between(
        source,
        "local function _GetListingKeystoneLevel(",
        "local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)",
    )
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
        "local function HashSnapshot(payload)",
    )

    key_idx = payload_body.index("keyLevel = _GetListingKeystoneLevel(")
    owned_idx = payload_body.index("if shouldUseOwnedKeystone then")

    assert key_idx < owned_idx


def test_payload_does_not_pack_raiderio_dungeon_rows_into_qr():
    source = _lua_source()
    payload_body = _slice_between(
        source,
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
        "local function BuildPayload(entry, applicantIDs, terminalClear)",
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
