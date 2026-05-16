param(
    [string]$OutputDir,
    [switch]$AllowDirty
)

$ErrorActionPreference = "Stop"

$AddonName = "ApplicantScout"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TocPath = Join-Path $RepoRoot "ApplicantScout.toc"

if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot "dist"
}

$RequiredFiles = @(
    "ApplicantScout.toc",
    "ApplicantScout.lua",
    "LICENSE",
    "THIRD-PARTY-NOTICES.md",
    "media\logo.png",
    "libs\qrencode.lua"
)
$ReleaseInputFiles = $RequiredFiles + @(
    ".pkgmeta",
    "CHANGELOG.md",
    "scripts\package-addon.ps1"
)

function Invoke-GitChecked {
    param(
        [string[]]$Arguments,
        [string]$ErrorMessage
    )

    & git -C $RepoRoot @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

function Assert-ZipContract {
    param(
        [string]$ArchivePath,
        [string[]]$ExpectedEntries
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $Entries = @($Zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    }
    finally {
        $Zip.Dispose()
    }

    foreach ($Expected in $ExpectedEntries) {
        if ($Entries -notcontains $Expected) {
            throw "Addon package is missing required entry: $Expected"
        }
    }

    foreach ($Entry in $Entries) {
        if ($Entry -notlike "$AddonName/*") {
            throw "Addon package entry is outside $AddonName/: $Entry"
        }
        if (
            $Entry -match "(^|/)\.git(/|$)" -or
            $Entry -match "(^|/)AGENTS\.md$" -or
            $Entry -match "(^|/)AUDIT\.md$" -or
            $Entry -match "(^|/)PLAN\.md$" -or
            $Entry -match "(^|/)NOTES\.md$" -or
            $Entry -match "(^|/)TODO\.md$" -or
            $Entry -match "(^|/)[^/]+\.private\.md$" -or
            $Entry -match "(^|/)SavedVariables(/|$)" -or
            $Entry -match "^$AddonName/docs/"
        ) {
            throw "Addon package contains forbidden entry: $Entry"
        }
    }
}

if (-not (Test-Path -LiteralPath $TocPath -PathType Leaf)) {
    throw "Missing TOC file: $TocPath"
}

$TocText = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
if ($TocText -notmatch "(?m)^##\s*Version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$") {
    throw "ApplicantScout.toc must contain a strict X.Y.Z '## Version:' value."
}
$Version = $Matches[1]

foreach ($RelativePath in $RequiredFiles) {
    $Source = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Missing required addon package file: $RelativePath"
    }
    Invoke-GitChecked `
        -Arguments @("ls-files", "--error-unmatch", "--", $RelativePath) `
        -ErrorMessage "Required addon package file is not tracked by git: $RelativePath"
}

if (-not $AllowDirty) {
    $DirtyEntries = @(
        & git -C $RepoRoot status --porcelain --untracked-files=no -- $ReleaseInputFiles
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect package input cleanliness."
    }
    if ($DirtyEntries.Count -gt 0) {
        throw (
            "Refusing to package from dirty release inputs. Commit or revert " +
            "these files, or rerun with -AllowDirty for a development smoke build:`n" +
            ($DirtyEntries -join "`n")
        )
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$ArchivePath = Join-Path $OutputDir "$AddonName-$Version.zip"
$TempArchive = Join-Path $OutputDir ".$AddonName-$Version.tmp.zip"
$StagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "$AddonName-package-$([System.Guid]::NewGuid().ToString('N'))"
$AddonStage = Join-Path $StagingRoot $AddonName

try {
    foreach ($RelativePath in $RequiredFiles) {
        $Source = Join-Path $RepoRoot $RelativePath
        $Destination = Join-Path $AddonStage $RelativePath
        $DestinationDir = Split-Path -Parent $Destination
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination
    }

    if (Test-Path -LiteralPath $TempArchive) {
        Remove-Item -LiteralPath $TempArchive -Force
    }

    Compress-Archive -LiteralPath $AddonStage -DestinationPath $TempArchive -CompressionLevel Optimal

    $ExpectedEntries = @($RequiredFiles | ForEach-Object { "$AddonName/$($_ -replace '\\', '/')" })
    Assert-ZipContract -ArchivePath $TempArchive -ExpectedEntries $ExpectedEntries

    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }
    Move-Item -LiteralPath $TempArchive -Destination $ArchivePath -Force
    Write-Host "Packed development-only addon ZIP: $ArchivePath"
}
finally {
    if (Test-Path -LiteralPath $TempArchive) {
        Remove-Item -LiteralPath $TempArchive -Force
    }
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
}
