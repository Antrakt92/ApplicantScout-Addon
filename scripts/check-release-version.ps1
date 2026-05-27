param(
    [string]$Tag = $env:GITHUB_REF_NAME,
    [string]$PairedCompanionRefOutputPath,
    [string]$PairedCompanionRoot,
    [switch]$RequirePublishedPairedCompanionAssets,
    [string]$GitHubCliPath = "gh",
    [int]$PublishedReleaseWaitSeconds = 120,
    [int]$PublishedReleasePollSeconds = 10
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

function Invoke-GitHubReleaseView {
    param(
        [string]$CliPath,
        [string]$Repo,
        [string]$ReleaseTag
    )

    $ErrorPath = [System.IO.Path]::GetTempFileName()
    try {
        $JsonLines = & $CliPath release view $ReleaseTag --repo $Repo --json "tagName,isDraft,isPrerelease,assets" 2> $ErrorPath
        $ExitCode = $LASTEXITCODE
        $ErrorRaw = Get-Content -LiteralPath $ErrorPath -Raw -ErrorAction SilentlyContinue
        $ErrorText = if ($null -eq $ErrorRaw) { "" } else { $ErrorRaw.Trim() }
        if ($ExitCode -ne 0) {
            $Message = "gh release view failed for $Repo $ReleaseTag with exit code $ExitCode."
            if ($ErrorText) {
                $Message = "$Message $ErrorText"
            }
            throw $Message
        }

        $JsonText = ($JsonLines -join "`n").Trim()
        if (-not $JsonText) {
            throw "gh release view returned empty JSON for $Repo $ReleaseTag."
        }
        try {
            return ($JsonText | ConvertFrom-Json)
        }
        catch {
            throw "gh release view returned malformed JSON for $Repo $ReleaseTag."
        }
    }
    finally {
        if (Test-Path -LiteralPath $ErrorPath) {
            Remove-Item -LiteralPath $ErrorPath -Force
        }
    }
}

function Test-GitHubReleaseAssets {
    param(
        [object]$Release,
        [string]$Repo,
        [string]$ReleaseTag,
        [string[]]$ExpectedAssets
    )

    if ($null -eq $Release) {
        throw "GitHub Release $ReleaseTag in $Repo was not returned by gh."
    }
    if ($Release.isDraft) {
        throw "GitHub Release $ReleaseTag in $Repo is still draft; publish the paired companion release before releasing ApplicantScout."
    }
    if ($Release.isPrerelease) {
        throw "GitHub Release $ReleaseTag in $Repo is marked prerelease; publish the paired stable companion release before releasing ApplicantScout."
    }

    $Assets = if ($null -eq $Release.assets) { @() } else { @($Release.assets) }
    $AssetNames = @($Assets | ForEach-Object { $_.name })
    foreach ($AssetName in $ExpectedAssets) {
        if ($AssetNames -notcontains $AssetName) {
            throw "GitHub Release $ReleaseTag in $Repo is missing asset: $AssetName"
        }
    }
}

function Wait-GitHubReleaseAssets {
    param(
        [string]$CliPath,
        [string]$Repo,
        [string]$ReleaseTag,
        [string[]]$ExpectedAssets,
        [int]$WaitSeconds,
        [int]$PollSeconds
    )

    if ($WaitSeconds -lt 0) {
        throw "PublishedReleaseWaitSeconds must be zero or greater."
    }
    if ($PollSeconds -lt 1) {
        throw "PublishedReleasePollSeconds must be at least 1."
    }

    $Deadline = (Get-Date).AddSeconds($WaitSeconds)
    $LastError = $null
    do {
        try {
            $Release = Invoke-GitHubReleaseView -CliPath $CliPath -Repo $Repo -ReleaseTag $ReleaseTag
            Test-GitHubReleaseAssets `
                -Release $Release `
                -Repo $Repo `
                -ReleaseTag $ReleaseTag `
                -ExpectedAssets $ExpectedAssets
            return
        }
        catch {
            $LastError = $_.Exception.Message
            if ((Get-Date) -ge $Deadline) {
                break
            }
            Start-Sleep -Seconds $PollSeconds
        }
    } while ($true)

    throw $LastError
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

if ($RequirePublishedPairedCompanionAssets) {
    $PairedCompanionTag = "v$PairedCompanionVersion"
    $ExpectedCompanionAssets = @(
        "ApplicantScoutCompanionSetup-$PairedCompanionVersion.exe",
        "ApplicantScoutCompanionSetup-$PairedCompanionVersion.exe.sha256",
        "ApplicantScoutCompanion-$PairedCompanionVersion-portable.zip"
    )
    Wait-GitHubReleaseAssets `
        -CliPath $GitHubCliPath `
        -Repo "Antrakt92/ApplicantScout-Companion" `
        -ReleaseTag $PairedCompanionTag `
        -ExpectedAssets $ExpectedCompanionAssets `
        -WaitSeconds $PublishedReleaseWaitSeconds `
        -PollSeconds $PublishedReleasePollSeconds
}

Write-Host "Release version check passed: $TagName -> $TagVersion"
Write-Host "Expected paired companion ref: v$PairedCompanionVersion"
