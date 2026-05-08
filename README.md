# ApplicantScout

Personal-tool WoW addon that feeds M+ applicant snapshots to Applicant Scout
Companion.

The addon is the in-game data-source half of a two-component setup. While you
host a Mythic+ listing, it renders a QR code in the UI and triggers
screenshots. The companion watches the WoW `Screenshots` folder,
decodes the ApplicantScout QR payloads, queries Warcraft Logs, and displays the
external overlay.

## Usage

1. Install `ApplicantScout\` into `_retail_\Interface\AddOns\`.
2. Reload WoW.
3. Start the local companion from the paired source/dev checkout. The public
   companion download link is intentionally not published yet; it will be added
   here when the companion release repo and installer are ready.
4. Create your Mythic+ listing as usual.
5. Keep ApplicantScout enabled while scouting applicants.

ApplicantScout defaults new Mythic+ listings to the `Competitive` playstyle.
Use `/apscout competitive off` or the settings panel to disable that helper.

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
/apscout reset          clear dedup cache and force a fresh snapshot
/apscout shotnow        force a snapshot now
/apscout qrvisible      keep the QR frame visible for debugging
/apscout qrmove         toggle QR move mode; Alt+drag the QR frame
/apscout qrreset        reset QR frame position to top-left
/apscout taintcheck     inspect LFG field secret-tagging diagnostics
/apscout debug [on|off] toggle debug logging
/apscout competitive [on|off] auto-select Competitive for M+ listings
```

## Transport

ApplicantScout emits versioned `APS1` snapshots through QR screenshots. The
payload is binary and CRC-checked. QR generation uses legacy hex encoding first,
then falls back to raw byte mode when a large snapshot would exceed QR capacity.
The companion accepts both forms.

The wire protocol is intentionally owned by the addon and companion together;
run both from matching source versions when developing transport changes.

## License

MIT
