param(
    [string]$Tag = $env:GITHUB_REF_NAME
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

function Get-SingleRegexMatch {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Description
    )

    $Text = Get-Content -Path $Path -Raw
    $Matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($Matches.Count -eq 0) {
        throw "Missing $Description in $Path"
    }
    if ($Matches.Count -gt 1) {
        throw "Found multiple $Description values in $Path"
    }
    return $Matches[0].Groups[1].Value
}

function Get-FirstRegexMatch {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Description
    )

    $Text = Get-Content -Path $Path -Raw
    $Match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $Match.Success) {
        throw "Missing $Description in $Path"
    }
    return $Match.Groups[1].Value
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

$ChangelogVersion = Get-FirstRegexMatch `
    -Path "CHANGELOG.md" `
    -Pattern "^##\s+([0-9]+\.[0-9]+\.[0-9]+)\s+-\s+.+$" `
    -Description "top changelog version"

$Errors = @()
if ($TocVersion -ne $TagVersion) {
    $Errors += "ApplicantScout.toc ## Version is $TocVersion, expected $TagVersion from tag $TagName."
}
if ($ChangelogVersion -ne $TagVersion) {
    $Errors += "CHANGELOG.md top entry is $ChangelogVersion, expected $TagVersion from tag $TagName."
}

if ($Errors.Count -gt 0) {
    throw ($Errors -join "`n")
}

Write-Host "Release version check passed: $TagName -> $TagVersion"
