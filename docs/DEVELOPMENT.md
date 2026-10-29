# ApplicantScout addon development reference

[Contributor setup](../CONTRIBUTING.md) · [Player guide](../README.md)

## Transport reference

Wire payload: compact v9 (`APS1`) snapshots carry optional RaiderIO, raid/M+
roster, leader-keystone context, and partial snapshot information. A v11 frame
preserves prior companion state when an applicant read is incomplete. Bounded
v10 fragment envelopes carry snapshots that exceed one reliable QR; the
companion applies them only after rebuilding the complete inner snapshot.

Keep QR/screenshot transport, capture cleanup, and stale-snapshot rejection
covered by the paired contract tests. Chat messages are not the transport.
Preserve the BSD-3-Clause notice when changing the bundled QR encoder.

## Development package

Keep each new `CHANGELOG.md` release list compact: put text beside every bullet,
with no blank lines between items or paragraphs inside an item. Long lines may
wrap onto indented continuation lines. Separate Added, Improved and Fixed lists
with headings. The release-version check validates the newest entry before
packaging; older entries stay unchanged.

From a clean addon checkout:

```powershell
.\scripts\package-addon.ps1
```

This creates a development-only addon ZIP at `dist\ApplicantScout-<version>.zip`
and checks its top-level `ApplicantScout/` folder. Use `-AllowDirty` only for a
local smoke build of pending changes. Marketplace packages come from the
BigWigs packager and [.pkgmeta](../.pkgmeta), with the full changelog and licence
notices. A development ZIP is not a marketplace release.
