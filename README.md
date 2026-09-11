# ApplicantScout: LFG & Party Overlay

<p>
  <a href="https://github.com/Antrakt92/ApplicantScout-Addon/releases/latest"><img alt="Latest addon release" src="https://img.shields.io/github/v/release/Antrakt92/ApplicantScout-Addon?style=for-the-badge"></a>
  <a href="https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest"><img alt="Companion required" src="https://img.shields.io/badge/Companion-required-ff5e7a?style=for-the-badge"></a>
  <img alt="Retail Midnight 12.x" src="https://img.shields.io/badge/Retail-Midnight%2012.x-7c5cff?style=for-the-badge">
  <img alt="Warcraft Logs plus RaiderIO" src="https://img.shields.io/badge/WCL%20%2B%20RaiderIO-overlay-00b8ff?style=for-the-badge">
</p>

**Check applicants before you invite.**

See Warcraft Logs performance, RaiderIO scores, and dungeon or raid experience
beside Group Finder. Compare applicants in one table, inspect players who
applied together, or switch to Party view to review your current group.

**You need both this WoW addon and the free ApplicantScout Companion for
Windows.** The addon collects group information. The Windows app displays the
overlay shown below.

**[Get the Windows companion](https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest)**
· **[Follow the setup guide](https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/docs/GETTING_STARTED.md)**

On the download page, choose `ApplicantScoutCompanionSetup-*.exe` under
**Assets**. Setup also requires a free Warcraft Logs account and API client;
the guide walks through creating one. You do not need your Blizzard password.

<p align="center">
  <img src="docs/visual/applicantscout-curseforge-raid-party-overlay.jpg" alt="Windows companion: raid applicants with Warcraft Logs performance and raid progress" width="45%">
  <img src="docs/visual/applicantscout-curseforge-mplus-overlay.jpg" alt="Windows companion: Mythic+ applicants with key fit, Warcraft Logs damage percentiles, and RaiderIO scores" width="45%">
</p>

*The Windows companion displays these tables beside WoW. Installing the addon
alone does not display them.*

## What You Can Check

- **Applicants:** compare Warcraft Logs performance, RaiderIO score, role, and
  item level without opening a separate profile for every player.
- **Grouped applications:** see each member's results as well as a combined
  Fit estimate for the group applying together.
- **Your current party or raid:** review the roster after inviting players or
  joining someone else's group.
- **Relevant experience:** see dungeon history for Mythic+ and progress for
  raid listings where the data is available.

Missing logs are marked as missing. ApplicantScout does not auto-invite players
or automate gameplay; you choose whom to invite.

The companion offers optional usage statistics, enabled when no preference has
been saved. Existing choices are preserved. Reports contain a random installation
ID, version and daily milestones; names, screenshots and credentials are excluded.
Participating companion installations send reports to the ApplicantScout service
hosted on Cloudflare. Turn sharing off in Companion Settings at any time.
[Details and how to turn sharing off](https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/docs/PRIVACY.md).

## Quick Setup

1. Install ApplicantScout through CurseForge, or download the packaged addon ZIP
   from [the latest addon release](https://github.com/Antrakt92/ApplicantScout-Addon/releases/latest).
2. Install ApplicantScout Companion from
   [the latest companion release](https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest).
   Use `ApplicantScoutCompanionSetup-*.exe`; the portable ZIP is mainly for
   manual/dev use.
3. Launch the companion and enter your Warcraft Logs Client ID/Secret.
   The [setup guide](https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/docs/GETTING_STARTED.md)
   explains where to create these and how to use **Test WCL**.
4. Set the active WoW `_retail_\Screenshots` folder in companion Settings.
5. Reload WoW, then host a Mythic+ or raid listing, or join a group and use
   Party view to review the current roster.

Manual addon installs should extract the packaged ZIP so the TOC is at
`_retail_\Interface\AddOns\ApplicantScout\ApplicantScout.toc`. Do not use
GitHub's automatic source-code ZIP for normal installs; it extracts to the wrong
folder name for WoW.

## What The Overlay Can Show

- Warcraft Logs raid and Mythic+ percentiles.
- RaiderIO current score, optional main-score context, and local RaiderIO
  dungeon/raid evidence when the RaiderIO addon data is available.
- Role, item level, grouped-applicant packages, and per-player rows.
- A neutral Fit estimate such as **~65** for the target key or raid, alongside
  coloured Normal, Heroic, Mythic, and M+ WCL results for the applying specialization.
  Compact headers and tooltips explain the values without filling the table with text.
- Target-key fit, dungeon history, and low-evidence markers for Mythic+.
- Current party/raid roster context after invites or after joining a group.
- Optional playstyle and Auto Hi controls for in-game quality-of-life.

Mythic+ Fit estimates how the available evidence matches the target key; it is
not a success probability or a Warcraft Logs percentile. The companion combines
named RaiderIO and WCL evidence once per dungeon. Hover Fit for evidence strength,
dungeon coverage and limitations. WCL results keep their percentile colours.
M+ WCL values measure damage for every role, including tanks and healers; they
do not measure healing, survival, or utility.

## How It Works

WoW addons cannot query Warcraft Logs directly from inside the game client.
ApplicantScout keeps the in-game addon small and uses public UI/screenshot APIs:

1. The addon watches your active Group Finder listing and current party/raid
   roster.
2. It renders compact QR snapshots and triggers normal WoW screenshots.
3. The companion watches the configured Screenshots folder, decodes
   ApplicantScout snapshots, fetches WCL data, reads optional local
   RaiderIO data, and updates the overlay.
4. The QR frame appears only during the screenshot capture window so it stays
   out of the way between snapshots.

QR transport pauses completely before LFG polling or payload/QR work during
combat, for the full active Mythic+ run, and during raid boss encounters. It
remains available out of combat in a raid, so you can keep recruiting between
pulls.

ApplicantScout temporarily raises screenshot quality and uses JPG format only
during each QR capture, then restores your prior screenshot settings after the
screenshot. `/apscout off` and the next `/reload` also restore an interrupted
capture lease defensively.

## Privacy And Trust

ApplicantScout does not read WoW memory, inject code, automate gameplay, or send
chat messages as a transport.

Trust notes for the companion:

- It does not ask for Blizzard credentials or account access.
- It watches only the configured WoW `Screenshots` folder for ApplicantScout QR
  payloads.
- If the RaiderIO addon is installed, it can read local RaiderIO addon database
  files under `_retail_\Interface\AddOns\RaiderIO\db` to enrich score/progress
  context.
- It stores Warcraft Logs API credentials locally under your Windows user
  profile.
- Decoded RaiderIO lookup payloads can be cached under
  `%LOCALAPPDATA%\applicant-scout\cache\raiderio-local`.
- It is source-available in the public companion repository.
- Current Windows builds are unsigned, so SmartScreen can warn on first install;
  the release also publishes a `.sha256` sidecar for file integrity, not
  publisher identity.

Before sharing support material publicly, redact `/apscout status` output,
`/apscout taintcheck` output, companion logs, QR screenshots, manual decode
output, `config.env`, `token.json`, `character-cache.json`,
`last-live-snapshot.json`, and `screenshot-manual-index-v2-*.json`. Treat the
entire `%LOCALAPPDATA%\applicant-scout\config\` and
`%LOCALAPPDATA%\applicant-scout\cache\` directories as private; do not attach
either directory wholesale. These files can include WCL Client ID/Secret,
OAuth access token, character names, realm names, applicant/roster snapshots,
listing titles/comments, screenshots folder paths, absolute screenshot file
paths, keystone/listing metadata, and WCL/RaiderIO evidence.

QR screenshots may remain if the companion is absent, interrupted, pointed at
the wrong folder, or the Screenshots folder is synced/shared before cleanup.

## Handy Slash Commands

The Group Finder panel stays focused on everyday applicant scouting, playstyle,
and Auto Hi controls. Advanced diagnostics and QR recovery remain available
through the slash commands below.

```text
/apscout on | off       enable/disable capture
/apscout toggle         flip enabled state
/apscout config         open/close settings panel
/apscout setup          show companion download and setup
/apscout status         show current state + QR diagnostics
/apscout playstyle [off|learning|relaxed|competitive|carry] set M+ default playstyle
/apscout reset          clear transport cache, queue fresh snapshot
/apscout shotnow        request snapshot while enabled; defers in combat/M+/boss fights
/apscout qrvisible      toggle persistent QR always-visible mode; off clears it
/apscout qrmove         toggle QR move mode (Alt+drag QR frame)
/apscout qrreset        reset QR frame position to top-left
/apscout taintcheck     probe C_LFGList field secret-tagging
/apscout debug [on|off] toggle debug logging
/apscout competitive [on|off] legacy alias for Competitive / Off
```

## Compatibility

- WoW Retail Midnight: Interface `120100`.
- Latest ApplicantScout addon release.
- Latest ApplicantScout Companion release.
- Wire payload: compact v9 (`APS1`) snapshots with optional RaiderIO, raid/M+
  roster, leader-keystone context, and partial snapshot handling. A v11 frame
  is used only when an incomplete applicant read must preserve prior companion
  state. Backlogs that exceed one reliable QR use bounded v10 fragment
  envelopes and are applied only after the complete inner snapshot is rebuilt.
- Classic-era clients are not supported.

## Troubleshooting

- Overlay stays empty: open companion Settings and confirm the Screenshots path
  points at the active `_retail_\Screenshots` folder.
- WoW side looks idle: run `/apscout status` while hosting a listing.
- Need a manual sync: keep ApplicantScout enabled and run `/apscout shotnow`.
  The request waits until combat, an active M+ run, or a boss encounter ends.
- Applicant state looks stale: run `/apscout reset` while transport is active.
- WCL cells stay empty: open companion Settings and use Test WCL.
- QR frame is in the way: run `/apscout qrmove`, Alt-drag it, then run the same
  command again to lock it. Use `/apscout qrreset` to restore the default
  position.

## Local Development

Package a development-only addon ZIP from a clean checkout:

```powershell
.\scripts\package-addon.ps1
```

The script emits `dist\ApplicantScout-<version>.zip`, verifies that the archive
contains a top-level `ApplicantScout\` addon folder, and refuses dirty release
inputs by default. Marketplace releases are produced by the BigWigs packager
from `.pkgmeta`; use the local ZIP only for smoke testing.

For a local Lua syntax check, run:

```powershell
luac5.1 -p ApplicantScout.lua
```

## Support

- Addon source and in-game issues:
  [github.com/Antrakt92/ApplicantScout-Addon](https://github.com/Antrakt92/ApplicantScout-Addon)
- Companion, installer, WCL setup, and overlay issues:
  [github.com/Antrakt92/ApplicantScout-Companion](https://github.com/Antrakt92/ApplicantScout-Companion)

## License

ApplicantScout is MIT licensed; see `LICENSE`.

The bundled `libs/qrencode.lua` library retains its upstream 3-clause BSD
license. See `THIRD-PARTY-NOTICES.md` and the source header in
`libs/qrencode.lua`.
