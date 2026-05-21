# ApplicantScout

> [!IMPORTANT]
> ApplicantScout is a **two-part tool**. Installing only the WoW addon will not
> show Warcraft Logs / RaiderIO parses by itself. You need both pieces:
>
> 1. **ApplicantScout addon** - installed in WoW through CurseForge or this
>    release.
> 2. **Applicant Scout Companion** - the Windows overlay that decodes the
>    screenshots and shows parses:
>    [download the latest companion](https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest).

ApplicantScout helps Mythic+ key hosts review applicants without turning the
in-game Group Finder into a spreadsheet. The addon captures applicant snapshots
from Blizzard's LFG UI, sends them through QR screenshots, and pairs with the
local Applicant Scout Companion overlay for Warcraft Logs, RaiderIO, role, group,
and key-fit context.

**Actively maintained. Feedback and suggestions are very welcome.**

![ApplicantScout companion overlay showing applicant fit, WCL percentiles, RaiderIO score, and grouped applicant context](docs/visual/applicantscout-overlay-alpha.png)

## What It Does

- Captures Mythic+ applicant snapshots while you host a listing.
- Sends data through QR screenshots instead of chat messages, memory reads, or
  gameplay automation.
- Feeds Applicant Scout Companion, which shows Warcraft Logs raid/Mythic+
  percentiles, RaiderIO current/main score context, role filters, grouped
  applicant packages, and a numeric fit score for your listed key.
- Keeps grouped applications visible together so you can judge packages, not
  just individual rows.
- Defaults new Mythic+ listings to the `Competitive` playstyle, with Off,
  Learning, Relaxed, Competitive, and Carry Offered choices available from the
  settings panel or slash commands.

## Requirements

- World of Warcraft Retail / Midnight 12.x.
- Applicant Scout Companion for the external overlay.
- Warcraft Logs API credentials configured in the companion.
- Optional: RaiderIO addon for current-season main-score and per-dungeon
  completed-key context.

## Installation

### CurseForge

Install ApplicantScout through the CurseForge app once the project is approved.
The CurseForge file installs only the in-game addon. You still need Applicant
Scout Companion for the overlay.

### Manual

1. Download the packaged addon ZIP, `ApplicantScout-*.zip`, from the latest
   GitHub Release.
2. Extract the ZIP so the TOC is at
   `_retail_\Interface\AddOns\ApplicantScout\ApplicantScout.toc`.
3. Do not use GitHub's automatic source-code ZIP for normal installs; it extracts
   to the wrong folder name for WoW.
4. Install and start Applicant Scout Companion from
   [the paired companion release](https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest).
5. Reload WoW.
6. Create your Mythic+ listing as usual and keep ApplicantScout enabled while
   scouting applicants.

## Using ApplicantScout

The QR frame defaults to the top-left of the UI and appears only during the
screenshot capture window so it stays out of the way between snapshots. Use
`/apscout qrvisible` for debugging, or `/apscout qrmove` and Alt-drag the QR
frame to move it.

ApplicantScout temporarily raises screenshot quality and uses JPG format while
enabled, then restores your prior screenshot settings when you turn it off with
`/apscout off`.

## Slash Commands

```text
/apscout on | off       enable or disable capture
/apscout toggle         flip enabled state
/apscout config         open or close the settings panel
/apscout status         show current state and QR diagnostics
/apscout playstyle [off|learning|relaxed|competitive|carry] set M+ default playstyle
/apscout reset          clear transport cache and queue a fresh snapshot
/apscout shotnow        force a snapshot now while enabled
/apscout qrvisible      keep the QR frame visible for debugging
/apscout qrmove         toggle QR move mode; Alt-drag the QR frame
/apscout qrreset        reset QR frame position to top-left
/apscout taintcheck     inspect LFG field secret-tagging diagnostics
/apscout debug [on|off] toggle debug logging
/apscout competitive [on|off] legacy alias for Competitive / Off
```

## Transport And Privacy

ApplicantScout emits versioned `APS1` snapshots through QR screenshots. The
payload is binary and CRC-checked. QR generation uses legacy hex encoding first,
then falls back to raw byte mode when a large snapshot would exceed QR capacity.
The companion accepts both forms.

ApplicantScout does not read WoW memory, inject code, automate gameplay, or send
chat messages as a transport. The addon renders QR snapshots and triggers normal
WoW screenshots. The companion watches only the configured WoW `Screenshots`
folder and stores Warcraft Logs credentials/cache files locally under the current
Windows user profile.

## Compatibility

- WoW Retail Midnight: Interface `120005, 120007`
- Latest ApplicantScout addon release
- Latest Applicant Scout Companion release
- Wire payload: compact v6, including optional RaiderIO main-score,
  target-relative completion data, and party/raid roster snapshots. The
  companion enriches highest timed key-per-dungeon context from the installed
  local RaiderIO database.
- Classic-era clients are not supported

## Troubleshooting

- Overlay stays empty: open companion Settings and confirm the Screenshots path
  points at the active `_retail_\Screenshots` folder.
- WoW side looks idle: run `/apscout status` while hosting a listing.
- Need a manual sync: keep ApplicantScout enabled and run `/apscout shotnow`.
- Applicant state looks stale: run `/apscout reset` while transport is active.
- WCL cells stay empty: open companion Settings and use Test WCL.
- QR frame is in the way: run `/apscout qrmove`, Alt-drag it, then run
  `/apscout qrmove` again to lock placement.

## Local Development

Package a development-only addon ZIP from a clean checkout:

```powershell
.\scripts\package-addon.ps1
```

The script emits a development-only addon ZIP at
`dist\ApplicantScout-<version>.zip` using the version in `ApplicantScout.toc`
and verifies that the archive contains a top-level `ApplicantScout\` addon
folder. Marketplace releases are produced by the BigWigs packager from
`.pkgmeta`; use this local ZIP only for smoke testing. The script refuses to
package dirty release inputs by default; use `-AllowDirty` only for local smoke
builds that will not be published.

For workspace-wide Lua syntax and LuaLS diagnostics, run this from the private
WOW coordination repo:

```powershell
.\scripts\check-wow-lua.ps1 -Project ApplicantScout
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
