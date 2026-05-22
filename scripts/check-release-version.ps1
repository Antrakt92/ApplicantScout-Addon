param(
    [string]$Tag = $env:GITHUB_REF_NAME,
    [string]$PairedCompanionRefOutputPath,
    [string]$PairedCompanionRoot
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

function Get-SingleRegexMatch {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Description
    )

    $FullPath = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Missing $Description file: $FullPath"
    }
    $Text = Get-Content -LiteralPath $FullPath -Raw -Encoding UTF8
    $Matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($Matches.Count -eq 0) {
        throw "Missing $Description in $Path"
    }
    if ($Matches.Count -gt 1) {
        throw "Found multiple $Description values in $Path"
    }
    return $Matches[0].Groups[1].Value
}

function Get-TopChangelogSection {
    param(
        [string]$Path
    )

    $FullPath = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $FullPath)) {
        throw "Missing changelog file: $FullPath"
    }
    $Text = Get-Content -LiteralPath $FullPath -Raw -Encoding UTF8
    $Options = [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $Match = [regex]::Match(
        $Text,
        "^##\s+([0-9]+\.[0-9]+\.[0-9]+)\s+-\s+.+?(?=^##\s+[0-9]+\.[0-9]+\.[0-9]+\s+-\s+|\z)",
        $Options
    )
    if (-not $Match.Success) {
        throw "Missing top changelog section in $Path"
    }
    return $Match
}

function Write-GitHubOutput {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    $OutputDirectory = Split-Path -Path $Path -Parent
    if ($OutputDirectory -and -not (Test-Path -LiteralPath $OutputDirectory)) {
        throw "GitHub output directory does not exist: $OutputDirectory"
    }
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText(
        $Path,
        "$Name=$Value`n",
        $Utf8NoBom
    )
}

function Compare-SemVer {
    param(
        [string]$Left,
        [string]$Right
    )

    $LeftParts = @($Left.Split(".") | ForEach-Object { [int]$_ })
    $RightParts = @($Right.Split(".") | ForEach-Object { [int]$_ })
    for ($Index = 0; $Index -lt 3; $Index++) {
        if ($LeftParts[$Index] -lt $RightParts[$Index]) {
            return -1
        }
        if ($LeftParts[$Index] -gt $RightParts[$Index]) {
            return 1
        }
    }
    return 0
}

function Get-CompanionReleaseMetadata {
    param(
        [string]$Root
    )

    $ResolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    $ReleaseNotesPath = Join-Path $ResolvedRoot "RELEASE_NOTES.md"
    if (-not (Test-Path -LiteralPath $ReleaseNotesPath)) {
        throw "Missing paired companion release notes: $ReleaseNotesPath"
    }
    $Text = Get-Content -LiteralPath $ReleaseNotesPath -Raw -Encoding UTF8
    $TopMatch = [regex]::Match(
        $Text,
        '(?ms)^##\s+([0-9]+\.[0-9]+\.[0-9]+)\s+-\s+.*?(?=^##\s+\d+\.\d+\.\d+\s+-\s+|\z)'
    )
    if (-not $TopMatch.Success) {
        throw "Missing top paired companion release notes entry in $ReleaseNotesPath"
    }
    $TopEntry = $TopMatch.Value
    $RequiredAddonMatch = [regex]::Match(
        $TopEntry,
        '(?m)^-\s+Requires the ApplicantScout WoW addon\s+`([0-9]+\.[0-9]+\.[0-9]+)`\.\s*$'
    )
    if (-not $RequiredAddonMatch.Success) {
        throw "Paired companion release notes do not name the required ApplicantScout addon version."
    }
    return @{
        Version = $TopMatch.Groups[1].Value
        RequiredAddonVersion = $RequiredAddonMatch.Groups[1].Value
    }
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    throw "Missing release tag. Pass -Tag vX.Y.Z or set GITHUB_REF_NAME."
}

$TagName = $Tag.Trim()
if ($TagName -match "^refs/tags/(.+)$") {
    $TagName = $Matches[1]
}

$TagVersion = if ($TagName.StartsWith("v")) {
    $TagName.Substring(1)
}
else {
    $TagName
}

if ($TagVersion -notmatch "^\d+\.\d+\.\d+$") {
    throw "Malformed release tag '$Tag'. Expected vX.Y.Z or X.Y.Z."
}

$TocVersion = Get-SingleRegexMatch `
    -Path "ApplicantScout.toc" `
    -Pattern "^##\s+Version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$" `
    -Description "TOC Version"

$TopChangelogMatch = Get-TopChangelogSection -Path "CHANGELOG.md"
$ChangelogVersion = $TopChangelogMatch.Groups[1].Value
$TopChangelogSection = $TopChangelogMatch.Value

$PairedCompanionMatches = [regex]::Matches(
    $TopChangelogSection,
    '(?i)(?:ApplicantScout\s+)?Companion\s+`?([0-9]+\.[0-9]+\.[0-9]+)`?',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$PairedCompanionVersions = @(
    $PairedCompanionMatches |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)

$Errors = @()
if ($TocVersion -ne $TagVersion) {
    $Errors += "ApplicantScout.toc ## Version is $TocVersion, expected $TagVersion from tag $TagName."
}
if ($ChangelogVersion -ne $TagVersion) {
    $Errors += "CHANGELOG.md top entry is $ChangelogVersion, expected $TagVersion from tag $TagName."
}
if ($PairedCompanionVersions.Count -eq 0) {
    $Errors += "CHANGELOG.md top entry must name exactly one paired ApplicantScout Companion version."
}
if ($PairedCompanionVersions.Count -gt 1) {
    $Errors += "CHANGELOG.md top entry names multiple paired ApplicantScout Companion versions: $($PairedCompanionVersions -join ', ')."
}

if ($Errors.Count -gt 0) {
    throw ($Errors -join "`n")
}

$PairedCompanionVersion = $PairedCompanionVersions[0]
if (-not [string]::IsNullOrWhiteSpace($PairedCompanionRoot)) {
    $CompanionMetadata = Get-CompanionReleaseMetadata -Root $PairedCompanionRoot
    if ($CompanionMetadata.Version -ne $PairedCompanionVersion) {
        throw "Paired companion release notes top entry is $($CompanionMetadata.Version), expected $PairedCompanionVersion from addon changelog."
    }
    if ((Compare-SemVer -Left $TagVersion -Right $CompanionMetadata.RequiredAddonVersion) -lt 0) {
        throw "Paired companion $PairedCompanionVersion requires addon $($CompanionMetadata.RequiredAddonVersion), but current addon tag is $TagVersion."
    }
}
if (-not [string]::IsNullOrWhiteSpace($PairedCompanionRefOutputPath)) {
    Write-GitHubOutput `
        -Path $PairedCompanionRefOutputPath `
        -Name "companion_ref" `
        -Value "v$PairedCompanionVersion"
}

Write-Host "Release version check passed: $TagName -> $TagVersion"
Write-Host "Expected paired companion ref: v$PairedCompanionVersion"
