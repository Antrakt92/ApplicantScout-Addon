# Changelog

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
