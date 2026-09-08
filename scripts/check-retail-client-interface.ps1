param(
    [string]$TocPath,
    [string]$ReadmePath,
    [string]$ClientVersion,
    [string]$WowExecutablePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($TocPath)) {
    $TocPath = Join-Path $RepoRoot "ApplicantScout.toc"
}
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    $ReadmePath = Join-Path $RepoRoot "README.md"
}

function Get-RetailInterfaceFromClientVersion {
    param([string]$Value)

    $Match = [regex]::Match(
        $Value.Trim(),
        '^(?:Version\s+)?(?<major>[0-9]{1,2})\.(?<minor>[0-9]{1,2})\.(?<patch>[0-9]{1,2})(?:\.[0-9]+)?$',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $Match.Success) {
        throw "Retail client version must use MAJOR.MINOR.PATCH[.BUILD], got '$Value'."
    }

    $Major = [int]$Match.Groups['major'].Value
    $Minor = [int]$Match.Groups['minor'].Value
    $Patch = [int]$Match.Groups['patch'].Value
    if ($Major -lt 10 -or $Minor -gt 99 -or $Patch -gt 99) {
        throw "Retail client version is outside the supported Interface format: '$Value'."
    }

    return [pscustomobject]@{
        Interface = ('{0:D2}{1:D2}{2:D2}' -f $Major, $Minor, $Patch)
        RetailVersion = ('{0}.{1}.{2}' -f $Major, $Minor, $Patch)
    }
}

$HasClientVersion = -not [string]::IsNullOrWhiteSpace($ClientVersion)
$HasWowExecutable = -not [string]::IsNullOrWhiteSpace($WowExecutablePath)
if ($HasClientVersion -eq $HasWowExecutable) {
    throw "Specify exactly one version source: -ClientVersion or -WowExecutablePath."
}

if ($HasWowExecutable) {
    if (-not (Test-Path -LiteralPath $WowExecutablePath -PathType Leaf)) {
        throw "WoW executable was not found: $WowExecutablePath"
    }
    $ClientVersion = (Get-Item -LiteralPath $WowExecutablePath).VersionInfo.ProductVersion
    if ([string]::IsNullOrWhiteSpace($ClientVersion)) {
        throw "WoW executable does not expose a product version: $WowExecutablePath"
    }
}

$Expected = Get-RetailInterfaceFromClientVersion -Value $ClientVersion
$Toc = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
$InterfaceHeaders = [regex]::Matches($Toc, '(?m)^##[\t ]+Interface:[\t ]*(?<value>[^\r\n]*)\r?$')
if ($InterfaceHeaders.Count -ne 1) {
    throw "TOC must contain exactly one ## Interface: header: $TocPath"
}
$InterfaceMatch = $InterfaceHeaders[0]

$Interfaces = @(
    $InterfaceMatch.Groups['value'].Value.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($Interfaces.Count -ne 1 -or $Interfaces[0] -notmatch '^[1-9][0-9]{5}$') {
    throw "TOC Interface must contain exactly one six-digit Retail Interface value, found '$($InterfaceMatch.Groups['value'].Value)'."
}
if ($Interfaces[0] -cne $Expected.Interface) {
    throw "TOC Interface must be exactly $($Expected.Interface) for installed Retail $($Expected.RetailVersion), found '$($Interfaces[0])'."
}

$Readme = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
$ExpectedReadmeLine = "- WoW Retail Midnight: Interface ``$($Expected.Interface)``."
if ($Readme -notmatch [regex]::Escape($ExpectedReadmeLine)) {
    throw "README compatibility line must match the installed Retail Interface: $ExpectedReadmeLine"
}

Write-Host "Retail $($Expected.RetailVersion) matches the single supported Interface $($Expected.Interface)."
