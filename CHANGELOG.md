# Changelog

## 0.4.1 - 24-May-2026 - Companion 0.7.0 raid fit release train

This paired addon + companion release keeps the QR transport on compact v7 while
shipping ApplicantScout Companion `0.7.0`, which makes raid listings show their
primary fit signal in the matching Normal/Heroic/Mythic column and keeps M+
evidence as neutral support.

### Fixed

- Fixed grouped non-leader sessions that could use the player's own bag key as a
  fallback for an unknown active listing. Owned-keystone fallback now stays
  host/leader-only.
- Fixed current party/raid roster snapshots missing inspected item level for
  non-self units when Blizzard exposes it through inspect data.
- Fixed roster inspect readiness treating specialization alone as complete when
  item-level data was still pending.
- Fixed roster inspect preflight using a helper before it was in local scope,
  which could block some inspect-settling roster snapshots.

### Improved

- Optional key-provider addons are now listed in `OptionalDeps`, allowing DBM,
  BigWigs, LibKeystone, or RaiderIO to load before ApplicantScout when present.
- Roster inspect cache invalidation now clears cached item level together with
  specialization data, reducing stale party/raid member evidence.
- Companion `0.7.0` adds raid-target fit cells, boss-level raid details,
  local RaiderIO raid-progress enrichment, neutral raid-context M+ support
  cells, auto-sized raid fit columns, and a sticky manual Party tab selection.

### Notes

- This addon release is paired with ApplicantScout Companion `0.7.0`.
- Wire payloads remain compact v7; keep the addon and companion on their
  matching current releases.

## 0.4.0 - 23-May-2026 - Companion 0.6.0 leader key release train

This paired addon + companion release adds leader-keystone calibration for
current groups, improves Party roster transport during active searches, and
ships ApplicantScout Companion `0.6.0` for the matching overlay behavior.

### Added

- Added a built-in LibKS-compatible party key shim. ApplicantScout can now read
  and answer party keystone requests without requiring BigWigs or another
  key-tracker addon, while still remaining compatible with addons that speak the
  same protocol.
- Added leader-keystone context to compact APS1 v7 QR payloads so the companion
  can automatically calibrate Mythic+ target key level from the current group
  leader.
- Added a transport heartbeat for active snapshots, helping the companion catch
  up if a QR screenshot was missed.
- Added an Auto Hi greeting that can fire once after you join another group.
- Added Auto Hi support for new party members, delayed to 10 seconds after they
  join so the greeting is less abrupt. Raid groups are excluded.
- Added in-game settings controls for Auto Hi and polished the default
  playstyle configuration surface.

### Fixed

- Fixed the companion being pushed to Party view when an active search/listing
  was still open but the applicant list temporarily dropped to zero.
- Fixed full Party snapshots missing the last accepted member by walking the
  live `player` and `party1..party4` units instead of deriving the roster only
  from the reported group count.
- Fixed Party roster changes that could be forgotten when a new member arrived
  before inspect/spec data was ready. The addon now waits briefly for usable
  roster details, then sends a fallback snapshot if needed.
- Fixed the Auto Hi join greeting not firing for solo listings.
- Fixed screenshot CVar restore ordering around terminal clear retries.

### Improved

- Reduced QR churn on roster changes by waiting for party inspect/spec data for
  a short preflight window before publishing, while still falling back instead
  of dropping the update.
- Hardened release CI and contract coverage around pinned workflow actions,
  release tooling, paired companion validation, and Lua transport fixtures.
- Companion `0.6.0` decodes APS1 v7, uses the leader key as the automatic
  Mythic+ target key when no manual override is set, keeps the Applicants tab
  focused while an active listing is open, supports Party context from a leader
  key even when the listing is not visible, and includes cache, updater,
  setup, seasonal, WCL evidence, and release-gate hardening.

### Notes

- This addon release is paired with ApplicantScout Companion `0.6.0`.
- Wire payloads advance to compact v7 for optional leader-keystone context.
  Keep the addon and companion on their matching current releases.

## 0.3.4 - 22-May-2026 - Companion 0.5.4 release train and party roster fixes

This paired addon release refreshes public addon copy for ApplicantScout
Companion `0.5.4` and hardens live Party roster snapshots while groups are
being assembled.

### Fixed

- Fixed Party snapshots getting stuck on a partial roster when a newly invited
  member was already in the WoW group but their unit row or specialization had
  not fully settled yet.
- Fixed combat-deferred party inspection blocking applicant-free Party snapshots
  from reaching the companion during active gameplay.
- Added `/apscout status` diagnostics for roster preflight block reasons and
  incomplete roster retry state.

### Changed

- No QR wire-format changes; payloads remain compact v6.
- This addon release is paired with ApplicantScout Companion `0.5.4`.
- Companion `0.5.4` improves launcher responsiveness, Mythic+ fit scoring,
  update/cache I/O, watcher detection, unknown-spec WCL fetch handling, stale
  WCL completion ordering, debug cache-TTL persistence, and empty applicant-list
  clears.

## 0.3.3 - 21-May-2026 - Companion 0.5.2 lifecycle hardening release train

This paired addon + companion release keeps the in-game transport aligned with
ApplicantScout Companion `0.5.2`, which hardens lifecycle watcher detection,
Warcraft Logs fetch scope, Mythic+ fit scoring, updater downloads, and
cache/config writes.

### Improved

- Reduced QR refresh churn while party and applicant roster snapshots are still
  settling, so the addon sends fewer redundant captures during busy group
  changes.
- Hardened roster-inspect batching around preflight, combat deferral, and quiet
  full-party snapshots.

### Fixed

- Fixed applicant snapshots losing priority behind roster preflight work during
  active applicant updates.
- Fixed empty applicant-list snapshots losing priority behind party inspect
  preflight after an applicant had already been shown, which could leave the
  companion overlay displaying a stale applicant while the in-game list was
  empty.
- Fixed transport batching paths that could otherwise delay fresh applicant
  snapshots while party inspection was still catching up.

### Notes

- No QR wire-format change since `0.3.0`; payloads remain compact v6.
- This addon release is paired with ApplicantScout Companion `0.5.2`.
- Companion `0.5.2` fixes lifecycle watcher false positives, avoids useless
  unknown-spec M+ WCL fetches, improves broad Mythic+ fit scoring around mixed
  RaiderIO/WCL evidence, and hardens updater/cache persistence edges.

## 0.3.2 - 20-May-2026 - Companion 0.5.1 overlay reliability release train

This paired addon + companion release keeps the in-game transport aligned with
ApplicantScout Companion `0.5.1`, which stabilizes the collapsed overlay
launcher, Applicants/Party tab focus, hover refreshes, and update lifecycle.
The addon also includes small transport and release-preflight hardening.

### Improved

- Added branch check coverage so addon transport contracts, release metadata,
  Lua syntax, and development packaging are checked before release branches are
  merged.
- Release workflow dependencies are pinned more tightly for safer package
  preflight and marketplace publishing.
- Public README copy now makes it clearer that feedback and suggestions are
  welcome while preserving the two-part addon + companion install guidance.

### Fixed

- Fixed the QR missing-library diagnostic so `/apscout status` can still report
  a useful setup error when the QR encoder is unavailable.
- Hardened terminal-clear transport edges so grouped `/apscout off` and
  no-listing cleanup paths do not accidentally send stale Party roster state.
- Fixed Party RaiderIO current-score preservation in the addon-to-companion
  payload path.

### Notes

- No QR wire-format change since `0.3.0`; payloads remain compact v6.
- This addon release is paired with ApplicantScout Companion `0.5.1`.
- Companion `0.5.1` fixes launcher visibility/drag/click behavior, keeps new
  listings focused on Applicants, and hardens watcher/updater/cache edges.

## 0.3.1 - 18-May-2026 - Companion 0.5.0 M+ ranking release train

This paired addon + companion release keeps the in-game transport aligned with
ApplicantScout Companion `0.5.0`, which improves Mythic+ applicant ranking,
group package scoring, and hover explanations. The addon also includes
post-`0.3.0` transport hardening for key-cache, Party spec-cache, and
terminal-clear edge cases.

### Improved

- Hosted-key cache diagnostics now preserve the relevant source/status detail,
  making `/apscout status` more useful when Blizzard listing data is generic,
  protected, or unavailable.
- Release packaging contracts were refreshed so the paired addon and companion
  checks cover the current v6 transport and package-shaping files.

### Fixed

- Fixed active Mythic+ key-cache lifecycle boundaries so ended, edited, or
  relisted groups do not reuse stale posted-key evidence.
- Fixed Party roster spec-cache invalidation so a grouped player's
  specialization change can refresh the companion Party row instead of reusing
  stale inspected spec context.
- Fixed grouped `/apscout off` terminal snapshots so the companion receives a
  true clear instead of a valid no-listing Party roster snapshot.

### Notes

- No QR wire-format change since `0.3.0`; payloads remain compact v6.
- This addon release is paired with ApplicantScout Companion `0.5.0`.
- Companion `0.5.0` improves M+ fit scoring, group ranking, loading/error
  ordering, RaiderIO fallback explanations, and top-panel geometry.

## 0.3.0 - 18-May-2026 - Companion 0.4.0 Party roster overlay

This paired addon + companion release adds live party/raid roster snapshots so
the companion can show the current group in a dedicated Party tab, even when no
new applicants are pending. It also keeps QR transport hidden between captures
and reduces repeated idle screenshots once a full group is already stable.

### Added

- Added v6 roster snapshots for the current party or raid, allowing the paired
  companion to show the full current group in its Party tab.
- Party-only snapshots now publish when the player is grouped without an active
  applicant listing, so the overlay can still inspect the assembled group.
- Roster snapshots now include enough current-player and inspected-party context
  for the companion to fetch Warcraft Logs / RaiderIO data for group members.

### Improved

- QR transport now shows only for the screenshot capture window and hides again
  immediately afterward, avoiding a permanent large QR frame while a party is
  assembled.
- The addon now polls meaningful party roster state changes and inspect-ready
  updates instead of depending only on join/leave events.
- Hosted key recovery now falls back through the owned keystone when Blizzard's
  active listing data is generic or protected.
- Roster snapshots dirty themselves after inspected party specs become ready,
  so the companion can update role/spec context without waiting for another
  applicant event.

### Fixed

- Fixed current-party snapshots not being emitted when the group existed but no
  applicant list was active.
- Fixed idle full-party sessions repeatedly showing QR and taking screenshots
  even though nobody joined, left, or changed inspect state.
- Fixed party roster snapshots missing spec context until inspect data became
  available.
- Fixed hosted-key detection falling back to an unknown or wrong level when the
  listing UI could not expose the key directly.

### Notes

- This addon release is paired with ApplicantScout Companion `0.4.0`.
- The paired companion uses the new Party tab and manual key control for current
  group review.

## 0.2.2 - 17-May-2026 - Companion 0.3.2 screenshot decode speedup

This paired addon release keeps the public addon release train aligned with
ApplicantScout Companion `0.3.2`.

### Changed

- No addon Lua runtime or wire-format changes.
- Companion `0.3.2` speeds up screenshot QR decoding by scanning the normal
  top-left transport region first and adds diagnostics for slow screenshot
  stable-wait versus QR decode stages.

## 0.2.1 - 17-May-2026 - Companion 0.3.1 WCL resilience hotfix

This paired addon release keeps the public addon release train aligned with
ApplicantScout Companion `0.3.1`.

### Changed

- No addon Lua runtime or wire-format changes.
- Companion `0.3.1` fixes slow Warcraft Logs timeout handling during busy
  applicant waves and keeps cached WCL lookups off the overlay UI launch path.

## 0.2.0 - 17-May-2026 - Companion 0.3.0 RaiderIO completion and dungeon keys

This paired addon + companion release adds compact RaiderIO completion signals
to the QR payload so the companion can judge real near-key experience alongside
Warcraft Logs parses. Per-dungeon RaiderIO rows are enriched by the companion
from the installed local RaiderIO database instead of being packed into every
QR screenshot. It also tightens live hosted-key detection and makes the
companion bring cached Warcraft Logs evidence into the overlay faster during
busy applicant bursts.

### Improved

- ApplicantScout payloads now include a compact RaiderIO completion summary for
  the hosted key: best completed key, best key for the listed dungeon, timed
  coverage around the target level, and completed coverage one level below.
- The paired companion now reads each applicant's highest timed RaiderIO key
  per dungeon from the installed RaiderIO addon database, allowing it to display
  RIO dungeon evidence beside Warcraft Logs key/percentile rows without
  overloading QR screenshots.
- The paired companion now ranks applicants with no current Warcraft Logs data
  from RaiderIO completion evidence instead of forcing them to the bottom.
- The paired companion now uses a combined Mythic+ scorecard: RaiderIO
  per-dungeon keys define completion readiness, Warcraft Logs defines
  performance quality, missing logs stay unknown instead of bad, and bad
  relevant logs are worse than no logs.
- The paired companion now shows Mythic+ fit as a numeric score plus key,
  coloured with the Warcraft Logs palette, instead of adding extra
  `TOP` / `FIT` / `OK` / `RISK` wording in M+ cells.
- The paired companion now uses localized LFG activity IDs and RaiderIO
  per-dungeon rows for same-dungeon fit, so localized clients can keep RIO and
  WCL evidence aligned.
- The paired companion now separates Warcraft Logs key level and percentile in
  hover details, so RaiderIO and WCL evidence is easier to scan during invites.
- The paired companion now applies cached Warcraft Logs results before queueing
  new API work, coalesces applicant/table refresh bursts, and shows active WCL
  fetches while quota data is still pending.
- The addon QR payload is back to the compact v5 shape: live LFG state plus the
  target-relative RaiderIO summary only. Static per-dungeon RIO strings stay out
  of QR transport.
- Forced QR snapshots now refresh the active LFG session immediately before
  building the payload, so `/apscout shotnow` and cleanup shots use the latest
  Blizzard listing state.
- Hidden QR force shots stay visible long enough for the screenshot capture path
  to finish before visibility cleanup runs.
- Support/debug commands and QR drag handling now guard more edge cases instead
  of surfacing Lua errors during troubleshooting.
- Addon release preflight now runs transport contract tests and stricter version
  checks before packaging.

### Fixed

- Fixed forced snapshots that could reuse stale session state after listing
  changes.
- Fixed cleanup/link paths around QR force shots that could miss the intended
  final clear/update capture.
- Fixed companion-side RaiderIO evidence display and scoring edge cases where
  RIO rows could be visible in the hover panel but ignored or underweighted by
  the fit formula.
- Fixed same-realm applicants whose LFG names omit `-Realm` sometimes showing a
  RaiderIO score but no RaiderIO dungeon rows in the companion.
- Fixed RaiderIO summary best-key signals using depleted runs; compact payload
  best keys now describe timed runs, matching the companion's local RaiderIO
  dungeon-row enrichment.
- Fixed listed Mythic+ key detection by remembering the clean key title/comment
  from the create/edit form before Blizzard hides the active listing text, so a
  lower posted key is not scored as the higher key in the host's bag.
- Fixed stale posted-key cache reuse when a later listing cannot expose a clean
  key title/comment during creation.
- Fixed paired companion edge cases where lower-key Warcraft Logs evidence or
  hyphenated realm names could hide stronger RaiderIO timed-key evidence.
- Fixed paired companion hover rows showing empty placeholder RIO/WCL badges
  when only one evidence source exists for a dungeon.
- Fixed prepared QR snapshots becoming excessively large when repeated
  per-dungeon RaiderIO names were embedded for every applicant.

### Notes

- The paired companion supports payloads through compact v5; RaiderIO dungeon
  rows are enriched locally by the companion instead of transported in QR.
- ApplicantScout remains the in-game data-source half of the setup; the desktop
  companion renders Warcraft Logs / RaiderIO context.
- Recommended companion version: `0.3.0` or newer.

## 0.1.6 - 16-May-2026 - Companion 0.2.4 live Mythic+ hardening

This paired addon + companion release improves live Mythic+ key detection,
Warcraft Logs retry behavior, and fallback applicant sorting during active
group listings.

### Improved

- The addon now uses the hosted owned-keystone activity and level when Blizzard
  exposes the active listing as generic `Mythic+`, so the companion can receive
  the real hosted key level instead of `+0`.
- `/apscout status` now prints the active listing quest ID, resolved activity
  name, owned-keystone activity/level, whether that fallback is being used, and
  the final derived key level.
- The companion now keeps sorting generic Mythic+ listings by visible M+ log
  evidence, with higher completed key levels ahead of low-key percentile spikes.
- Temporary Warcraft Logs server errors and read timeouts are now retryable, so
  applicants are less likely to stay stuck as `?` after transient WCL failures.

### Fixed

- Fixed hosted Mythic+ listings sometimes being treated as unknown `+0` keys
  when the Blizzard active-entry payload did not expose the concrete key level.
- Fixed WCL HTTP 5xx responses and network timeouts sometimes behaving like
  permanent applicant failures.

### Notes

- No wire-format changes since `0.1.4`; the companion still supports
  ApplicantScout payloads through v4.
- ApplicantScout remains the in-game data-source half of the setup; the desktop
  companion renders Warcraft Logs / RaiderIO context.
- Recommended companion version: `0.2.4` or newer.

## 0.1.5 - 15-May-2026 - Companion 0.2.3 lifecycle hardening

This paired addon + companion release tightens the QR screenshot pipeline,
update install flow, and live-panel suppression behavior.

### Improved

- The in-game addon now recomputes QR suppression immediately after hooking a
  newly loaded Blizzard info panel that is already visible. First-opening panels
  such as Encounter Journal, Achievements, Collections, or Settings should no
  longer leave the QR visible until a later event.
- The companion now surfaces marker-bearing screenshot decode failures directly
  in the overlay footer as `shot failed`, with the file path and parse/CRC
  reason in the tooltip.
- Companion Settings and tray update actions now share an update-in-progress
  state, so repeated clicks cannot start duplicate installer/download workers.

### Fixed

- Fixed corrupt ApplicantScout QR screenshots being deleted after a parse
  failure without any visible companion feedback.
- Fixed stale screenshot watcher signals after changing the Screenshots folder;
  old-path snapshots and clears are ignored after a replacement watcher becomes
  active.
- Fixed no-system-tray sessions so the companion does not disable
  last-window-close quitting when no tray control surface exists.
- Fixed pending overlay geometry saves being lost on tray/control quit paths
  immediately after moving or resizing the window.

### Notes

- No wire-format changes since `0.1.4`; the companion still supports
  ApplicantScout payloads through v4.
- ApplicantScout remains the in-game data-source half of the setup; the desktop
  companion renders Warcraft Logs / RaiderIO context.
- Recommended companion version: `0.2.3` or newer.

## 0.1.4 - 15-May-2026 - Companion 0.2.2 scoring and update flow

This paired addon + companion release focuses on making Mythic+ fit scoring
more trustworthy and making companion updates easier to notice and install.

### Changed

- Reworked the companion's Mythic+ fit formula so relevant Warcraft Logs bracket
  performance is the primary signal.
- Key level, same-dungeon evidence, profile consistency, and RaiderIO still
  matter, but they no longer turn weak logs into a good-looking score.
- Sparse coverage is now treated as weaker evidence instead of a free score
  bonus.
- Low-key farm parses no longer inflate scores for much higher hosted keys.
- Very high-key evidence still helps, but low parses at very high keys are
  bounded so they do not look better than they should.
- Fit labels now line up with the visible WCL-style color bands:
  - `0-49`: `RISK`
  - `50-69`: `OK`
  - `70-84`: `FIT`
  - `85+`: `TOP`

### Improved

- The companion update install action now uses a clearer title-bar download
  icon.
- When the companion starts with WoW and finds an installable update, Settings
  can open with a direct update prompt instead of staying quietly hidden.
- Self-updates now return the user to the visible companion Settings flow after
  installing.

### Fixed

- Fixed cases where applicants with all-grey or mostly-grey Mythic+ logs could
  show as blue or overly positive.
- Fixed high current or main RaiderIO from rescuing weak WCL evidence into an
  inflated Mythic+ fit.
- Fixed poor extra dungeon logs accidentally reducing sparse-evidence penalties.
- Fixed mixed-bracket cases where old low-key farm logs could distort the fit
  for the hosted key.
- Fixed a visual contradiction where a blue-range numeric score could still be
  labelled `RISK`.

### Previous paired update included

- Added the compact Ko-fi support heart in companion Settings.
- Added the in-app update install icon that appears only when a valid companion
  update is available.
- Added companion version text to Settings and first-run window titles.
- Refreshed the CurseForge overlay screenshot for the addon page.
- Defaulted first-run Warcraft Logs data scope to Mythic+ only.
- Simplified companion Settings: close hides to tray, full quit lives in the
  tray menu, and secondary actions moved into a cleaner footer/menu layout.
- Matched Mythic+ parse colors to Warcraft Logs buckets.
- Split group applicant rows into package fit and individual member fit so
  group score and player score are no longer visually mixed.
- Hardened the updater repository target, installer metadata checks, installer
  error visibility, and duplicate install boundaries.
- Fixed `Test WCL` status being overwritten by `Saved`.
- Hardened Warcraft Logs cache, quota handling, stale worker lifecycle, and
  group scoring edge cases.

### Notes

- No Lua runtime or wire-format changes since `0.1.3`.
- ApplicantScout remains the in-game data-source half of the setup; the desktop
  companion renders Warcraft Logs / RaiderIO context.
- Recommended companion version: `0.2.2` or newer.

## 0.1.3 - 15-May-2026 - Companion 0.2.0 release train

### Changed

- Refreshed the public addon release for the paired Applicant Scout Companion
  `0.2.0` release.
- Updated public install copy to point users at the latest companion release
  without pinning a companion version in the addon README.

### Notes

- No Lua runtime or wire-format changes since `0.1.2`.
- ApplicantScout remains the in-game data-source half of the setup; the desktop
  companion renders Warcraft Logs / RaiderIO context.

## 0.1.2 - 14-May-2026 - Wago publishing

### Added

- Added Wago Addons release metadata and automated Wago upload support.

## 0.1.1 - 13-May-2026 - CurseForge publishing polish

### Changed

- Added CurseForge project metadata so automated uploads target the public
  ApplicantScout project.
- Updated public copy to use stable companion release links and the current
  public addon/companion repository names.
- Refreshed the marketplace logo to match the in-game applicant parse overlay.

### Fixed

- Fixed the Windows release workflow Lua compiler lookup used by tag preflight.

## 0.1.0 - 12-May-2026 - First public release

### Added

- Added the in-game ApplicantScout addon for Mythic+ applicant capture.
- Added QR screenshot transport for Applicant Scout Companion.
- Added support for grouped applicants, playstyle selection, QR movement, manual
  sync commands, and diagnostic status output.
- Added optional RaiderIO main-score transport when RaiderIO exposes the data.

### Notes

- ApplicantScout requires Applicant Scout Companion for the external WCL/RaiderIO
  overlay.
- The addon uses normal WoW screenshots for transport. It does not read memory,
  inject code, automate gameplay, or use chat messages as a data channel.
