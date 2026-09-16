# Contributing

ApplicantScout has two parts: this Lua addon captures Group Finder and roster
data; the [Windows companion](https://github.com/Antrakt92/ApplicantScout-Companion)
decodes screenshots and displays results. Changes to the QR format must remain
compatible across both repositories.

## Report A Problem

For in-game behaviour, open an [addon issue](https://github.com/Antrakt92/ApplicantScout-Addon/issues).
For the overlay, installer, or Warcraft Logs setup, use
[companion issues](https://github.com/Antrakt92/ApplicantScout-Companion/issues).
Include both versions, your WoW version, the steps to reproduce, and what you
expected. Remove credentials, character information, and local paths from logs
and screenshots before attaching them. See [README.md](README.md#support-and-contributions)
and [SECURITY.md](SECURITY.md) for reporting guidance.

## Set Up The Checkouts

Use Windows, PowerShell, Git, Python 3.13, and Lua 5.1. Keep the repositories
beside each other:

```text
ApplicantScout-Addon/
ApplicantScout-Companion/
```

From the parent directory:

```powershell
git clone https://github.com/Antrakt92/ApplicantScout-Addon.git
git clone https://github.com/Antrakt92/ApplicantScout-Companion.git
cd ApplicantScout-Companion
py -3.13 -m venv .venv
.\.venv\Scripts\python -m pip install -r constraints-release.txt
.\.venv\Scripts\python -m pip install -e '.[dev]' -c constraints-release.txt
```

Put `lua5.1` and `luac5.1` on PATH. CI uses Lua 5.1.5; its exact package and
checksum are recorded in [.github/workflows/check.yml](.github/workflows/check.yml).
For LuaLS, download the Windows x64 archive specified in
[scripts/tool-version-locks.json](scripts/tool-version-locks.json), verify its
SHA-256 against that file, and extract it. Pass the extracted executable to the
check below. The script rejects a different LuaLS version.

## Run Checks

From `ApplicantScout-Companion`:

```powershell
.\scripts\check.ps1 -AddonRoot ..\ApplicantScout-Addon
```

This runs Python tests, lint and type checks, visual checks, Lua syntax checks,
and the addon/companion contracts. Use the companion's `.venv` for Python work.
See its [contributor guide](https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/CONTRIBUTING.md)
for setup details and focused checks.

Then, from `ApplicantScout-Addon`, run LuaLS diagnostics using the verified tool:

```powershell
.\scripts\check-lua.ps1 -LuaLanguageServer '<extracted LuaLS directory>\bin\lua-language-server.exe'
git diff --check
```

A quick syntax check is `luac5.1 -p ApplicantScout.lua libs/qrencode.lua`.
It does not replace the paired checks or LuaLS diagnostics.

For runtime changes, also test in WoW: login and `/reload`, host a listing,
receive and remove applicants, join or leave a group, and enter and leave combat.
Verify capture pauses during an active Mythic+ run and raid boss encounters.
Offline tests cannot establish live protected-API behaviour.

## Transport Reference

Wire payload: compact v9 (`APS1`) snapshots carry optional RaiderIO, raid/M+
roster, leader-keystone context, and partial snapshot information. A v11 frame
preserves prior companion state when an applicant read is incomplete. Bounded
v10 fragment envelopes carry snapshots that exceed one reliable QR; the
companion applies them only after rebuilding the complete inner snapshot.

Keep QR/screenshot transport, capture cleanup, and stale-snapshot rejection
covered by the paired contract tests. Chat messages are not the transport.
Preserve the BSD-3-Clause notice when changing the bundled QR encoder.

## Development Package

From a clean addon checkout:

```powershell
.\scripts\package-addon.ps1
```

This creates a development-only addon ZIP at `dist\ApplicantScout-<version>.zip`
and checks its top-level `ApplicantScout/` folder. Use `-AllowDirty` only for a
local smoke build of pending changes. Marketplace packages come from the
BigWigs packager and [.pkgmeta](.pkgmeta), with the full changelog and licence
notices. A development ZIP is not a marketplace release.

## Pull Requests

Keep one change focused on one problem. Explain the behaviour before and after,
list the checks you ran, and note any live WoW checks still needed. Add a
regression test for behaviour fixes. If the transport changes, link the matching
companion change and test both checkouts together. Keep credentials, real-player
screenshots, generated build output, and local configuration out of commits.
