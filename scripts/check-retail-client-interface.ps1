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
        ForEach-Object { $_.Trim() }
)
if ($Interfaces.Count -eq 0 -or @($Interfaces | Where-Object { $_ -notmatch '^[1-9][0-9]{5}$' }).Count -gt 0) {
    throw "TOC Interface must contain comma-separated six-digit Retail Interface values without empty entries, found '$($InterfaceMatch.Groups['value'].Value)'."
}
if (@($Interfaces | Select-Object -Unique).Count -ne $Interfaces.Count) {
    throw "TOC Interface must not contain duplicate values."
}
if ($Interfaces -cnotcontains $Expected.Interface) {
    throw "TOC Interface must include $($Expected.Interface) for Retail $($Expected.RetailVersion), found '$($Interfaces -join ', ')'."
}

$Readme = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
$InterfaceLabel = if ($Interfaces.Count -eq 1) { "Interface" } else { "Interfaces" }
$ExpectedReadmeLine = "- WoW Retail Midnight: $InterfaceLabel ``$($Interfaces -join ', ')``."
if ($Readme -notmatch [regex]::Escape($ExpectedReadmeLine)) {
    throw "README compatibility line must match every declared Retail Interface: $ExpectedReadmeLine"
}

Write-Host "Retail $($Expected.RetailVersion) matches supported Interface $($Expected.Interface) (declared: $($Interfaces -join ', '))."
