# Changelog

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
