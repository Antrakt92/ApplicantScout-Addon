# ApplicantScout

Personal-tool WoW addon that feeds M+ applicant snapshots to Applicant Scout
Companion.

The addon is the in-game data-source half of a two-component setup. While you
host a Mythic+ listing, it renders a QR code in the UI and triggers
screenshots. The companion watches the WoW `Screenshots` folder,
decodes the ApplicantScout QR payloads, queries Warcraft Logs, and displays the
external overlay. If RaiderIO is installed, ApplicantScout also includes the
applicant's current-season main score when RaiderIO exposes one.

## Usage

1. Install `ApplicantScout\` into `_retail_\Interface\AddOns\`.
2. Reload WoW.
3. Install and start ApplicantScout Companion. Public companion builds are
   planned for `Antrakt92/ApplicantScout-Companion` GitHub Releases; until the
   first release is published, run the companion from the paired source/dev
   checkout.
4. Create your Mythic+ listing as usual.
5. Keep ApplicantScout enabled while scouting applicants.

ApplicantScout defaults new Mythic+ listings to the `Competitive` playstyle.
Use the settings panel or `/apscout playstyle ...` to choose Off, Learning,
Relaxed, Competitive, or Carry Offered. The legacy `/apscout competitive off`
alias still disables the helper.

The QR frame defaults to the top-left of the UI and stays visible during an
active capture session so the screenshot transport is reliable. Use
`/apscout qrmove` and Alt+drag the QR frame to move it. ApplicantScout
temporarily raises screenshot quality and uses JPG format while enabled, then
restores your prior screenshot settings when you turn it off with `/apscout off`.

## Slash Commands

```text
/apscout on | off       enable or disable capture
/apscout toggle         flip enabled state
/apscout config         open or close the settings panel
/apscout status         show current state and QR diagnostics
/apscout playstyle [off|learning|relaxed|competitive|carry] set M+ default playstyle
/apscout reset          clear dedup cache and force a fresh snapshot
/apscout shotnow        force a snapshot now
/apscout qrvisible      keep the QR frame visible for debugging
/apscout qrmove         toggle QR move mode; Alt+drag the QR frame
/apscout qrreset        reset QR frame position to top-left
/apscout taintcheck     inspect LFG field secret-tagging diagnostics
/apscout debug [on|off] toggle debug logging
/apscout competitive [on|off] legacy alias for Competitive / Off
```

## Transport

ApplicantScout emits versioned `APS1` snapshots through QR screenshots. The
payload is binary and CRC-checked. QR generation uses legacy hex encoding first,
then falls back to raw byte mode when a large snapshot would exceed QR capacity.
The companion accepts both forms.

The wire protocol is intentionally owned by the addon and companion together;
run compatible addon and companion versions when developing transport changes.
ApplicantScout addon `0.1.0` pairs with ApplicantScout Companion `0.1.0` and
uses wire v4 for optional RaiderIO main-score data in the companion's
`current [main]` RIO display and sorting fallback.

## Companion Trust Model

The addon and companion use QR screenshots only. ApplicantScout does not read
WoW memory, inject code, automate gameplay, or use chat messages as a transport.
Warcraft Logs credentials and OAuth/cache files are stored locally by the
companion under the current Windows user profile.

## License

MIT; see `LICENSE`.

The bundled `libs/qrencode.lua` library retains its upstream 3-clause BSD
license header.
