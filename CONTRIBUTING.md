# Contributing to ApplicantScout

[Player guide](README.md) · [Development reference](docs/DEVELOPMENT.md) · [Security](SECURITY.md)

## Report a problem

Use [addon issues](https://github.com/Antrakt92/ApplicantScout-Addon/issues)
for in-game problems and
[companion issues](https://github.com/Antrakt92/ApplicantScout-Companion/issues)
for the overlay, installer or Warcraft Logs setup. Include both versions,
your WoW build, reproduction steps and expected result. Redact credentials
and player data before posting logs or screenshots.

## Set up the checkouts

Keep `ApplicantScout-Addon` and `ApplicantScout-Companion` beside each other.
Follow the companion's [Windows setup instructions](https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/CONTRIBUTING.md)
for Python, dependencies and Lua 5.1.

## Run checks

From `ApplicantScout-Companion`:

```powershell
.\scripts\check.ps1 -AddonRoot ..\ApplicantScout-Addon
```

This checks Python, visual baselines, addon syntax and the shared contracts.
For addon LuaLS checks, download the Windows x64 archive in
[`scripts/tool-version-locks.json`](scripts/tool-version-locks.json), verify its
SHA-256 and extract it. From `ApplicantScout-Addon`, run:

```powershell
.\scripts\check-lua.ps1 -LuaLanguageServer '<extracted LuaLS directory>\bin\lua-language-server.exe'
git diff --check
```

Runtime changes also need login, `/reload`, listing and roster changes,
combat entry/exit, an active Mythic+ run and a raid boss encounter. Check that
capture pauses and resumes in the right states.

## Submit a change

Keep the change focused and include regression coverage and check results.
Transport changes must remain compatible with the companion and be checked
in both repositories. Preserve the QR encoder's BSD-3-Clause notice and full
changelog history. Do not commit credentials, player data or build archives.

See the [development reference](docs/DEVELOPMENT.md) for the wire format,
changelog format and local development packages.
