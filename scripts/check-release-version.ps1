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

function Assert-PublicInstallLinksUseLatest {
    param(
        [string]$Name,
        [string]$Text,
        [string[]]$RequiredLatestUrls
    )

    $LinkErrors = @()
    foreach ($Url in $RequiredLatestUrls) {
        if (-not $Text.Contains($Url)) {
            $LinkErrors += "$Name does not point installs at $Url."
        }
    }

    $PinnedPatterns = @(
        'https://github\.com/Antrakt92/(ApplicantScout-Addon|ApplicantScout-Companion)/(releases(?!/latest)(?:[/?#\s\)\]\}]|$)|archive(/|$)|archive/refs/tags/|zipball/|tarball/)',
        '\bApplicantScout\s+WoW\s+addon\s+`?\d+\.\d+\.\d+`?',
        '\bApplicantScout\s+Companion\s+`?\d+\.\d+\.\d+`?',
        '\bApplicantScout-v?\d+\.\d+\.\d+\.zip\b',
        '\bApplicantScoutCompanionSetup-\d+\.\d+\.\d+\.exe(?:\.sha256)?\b',
        '\bApplicantScoutCompanion-\d+\.\d+\.\d+-portable\.zip\b'
    )
    foreach ($Pattern in $PinnedPatterns) {
        if ([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $LinkErrors += "$Name pins install/version copy; use releases/latest for cross-component docs."
            break
        }
    }

    return $LinkErrors
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
        $JsonLines = & $CliPath release view $ReleaseTag --repo $Repo --json "tagName,isDraft,isPrerelease,isImmutable,assets" 2> $ErrorPath
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
        [string[]]$ExpectedAssets,
        [string[]]$ProtectedAssetPatterns = @()
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
    if ($Release.isImmutable -isnot [bool] -or -not $Release.isImmutable) {
        throw "GitHub Release $ReleaseTag in $Repo must be immutable before releasing ApplicantScout."
    }

    $Assets = if ($null -eq $Release.assets) { @() } else { @($Release.assets) }
    $AssetNames = @($Assets | ForEach-Object { $_.name })
    foreach ($AssetName in $ExpectedAssets) {
        if ($AssetNames -notcontains $AssetName) {
            throw "GitHub Release $ReleaseTag in $Repo is missing asset: $AssetName"
        }
    }
    foreach ($AssetName in $AssetNames) {
        if ($ExpectedAssets -contains $AssetName) {
            continue
        }
        foreach ($Pattern in $ProtectedAssetPatterns) {
            if ($AssetName -match $Pattern) {
                throw "GitHub Release $ReleaseTag in $Repo has unexpected asset: $AssetName"
            }
        }
    }
}

function Wait-GitHubReleaseAssets {
    param(
        [string]$CliPath,
        [string]$Repo,
        [string]$ReleaseTag,
        [string[]]$ExpectedAssets,
        [string[]]$ProtectedAssetPatterns = @(),
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
                -ExpectedAssets $ExpectedAssets `
                -ProtectedAssetPatterns $ProtectedAssetPatterns
            return $Release
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

function Invoke-GitHubCliText {
    param(
        [string]$CliPath,
        [string[]]$Arguments,
        [string]$Description
    )

    $ErrorPath = [System.IO.Path]::GetTempFileName()
    try {
        $OutputLines = & $CliPath @Arguments 2> $ErrorPath
        $ExitCode = $LASTEXITCODE
        $ErrorRaw = Get-Content -LiteralPath $ErrorPath -Raw -ErrorAction SilentlyContinue
        $ErrorText = if ($null -eq $ErrorRaw) { "" } else { $ErrorRaw.Trim() }
        if ($ExitCode -ne 0) {
            $Message = "$Description failed with exit code $ExitCode."
            if ($ErrorText) {
                $Message = "$Message $ErrorText"
            }
            throw $Message
        }

        $OutputText = ($OutputLines -join "`n").Trim()
        if (-not $OutputText) {
            throw "$Description returned empty output."
        }
        return $OutputText
    }
    finally {
        if (Test-Path -LiteralPath $ErrorPath) {
            Remove-Item -LiteralPath $ErrorPath -Force
        }
    }
}

function Resolve-GitHubTagCommit {
    param(
        [string]$CliPath,
        [string]$Repo,
        [string]$ReleaseTag
    )

    $RefText = Invoke-GitHubCliText `
        -CliPath $CliPath `
        -Arguments @("api", "repos/$Repo/git/ref/tags/$ReleaseTag") `
        -Description "Exact GitHub tag lookup for $Repo $ReleaseTag"
    try {
        $Ref = $RefText | ConvertFrom-Json
    }
    catch {
        throw "Exact GitHub tag lookup returned malformed JSON for $Repo $ReleaseTag."
    }
    if ([string]$Ref.ref -cne "refs/tags/$ReleaseTag") {
        throw "Exact GitHub tag lookup returned the wrong ref for $Repo $ReleaseTag."
    }

    $Object = $Ref.object
    for ($Depth = 0; $Depth -lt 5; $Depth++) {
        $ObjectType = [string]$Object.type
        $ObjectSha = [string]$Object.sha
        if ($ObjectSha -notmatch '^[0-9a-f]{40}$') {
            throw "GitHub tag $ReleaseTag in $Repo returned an invalid object SHA."
        }
        if ($ObjectType -ceq "commit") {
            return $ObjectSha
        }
        if ($ObjectType -cne "tag") {
            throw "GitHub tag $ReleaseTag in $Repo points to unsupported object type: $ObjectType"
        }

        $TagText = Invoke-GitHubCliText `
            -CliPath $CliPath `
            -Arguments @("api", "repos/$Repo/git/tags/$ObjectSha") `
            -Description "Annotated GitHub tag peel for $Repo $ReleaseTag"
        try {
            $TagObject = $TagText | ConvertFrom-Json
        }
        catch {
            throw "Annotated GitHub tag lookup returned malformed JSON for $Repo $ReleaseTag."
        }
        $Object = $TagObject.object
    }

    throw "GitHub tag $ReleaseTag in $Repo exceeds the supported annotated-tag depth."
}

function Test-PublishedCompanionManifest {
    param(
        [string]$CliPath,
        [object]$Release,
        [string]$Repo,
        [string]$ReleaseTag,
        [string]$ManifestName,
        [string[]]$ExpectedPayloadAssets,
        [string]$AddonTag
    )

    $Assets = @($Release.assets)
    $ManifestAssets = @($Assets | Where-Object { $_.name -ceq $ManifestName })
    if ($ManifestAssets.Count -ne 1) {
        throw "GitHub Release $ReleaseTag in $Repo must contain exactly one $ManifestName asset."
    }
    $ManifestAsset = $ManifestAssets[0]
    $ManifestApiUrl = [string]$ManifestAsset.apiUrl
    if ($ManifestApiUrl -notmatch '^https://api\.github\.com/repos/Antrakt92/ApplicantScout-Companion/releases/assets/[0-9]+$') {
        throw "GitHub Release $ReleaseTag in $Repo returned an invalid manifest asset API URL."
    }

    $ManifestText = Invoke-GitHubCliText `
        -CliPath $CliPath `
        -Arguments @("api", "-H", "Accept: application/octet-stream", $ManifestApiUrl) `
        -Description "Paired companion release manifest download"
    try {
        $Manifest = $ManifestText | ConvertFrom-Json
    }
    catch {
        throw "Paired companion release manifest is malformed JSON."
    }

    if ($Manifest.schemaVersion -isnot [long] -and $Manifest.schemaVersion -isnot [int]) {
        throw "Paired companion release manifest schemaVersion must be an integer."
    }
    if ([long]$Manifest.schemaVersion -ne 2) {
        throw "Unsupported paired companion release manifest schemaVersion: $($Manifest.schemaVersion)"
    }
    if ([string]$Manifest.repository -cne $Repo -or [string]$Manifest.purpose -cne "Release") {
        throw "Paired companion release manifest repository or purpose does not match the published release."
    }
    if ([string]$Manifest.tag -cne $ReleaseTag) {
        throw "Paired companion release manifest tag does not match $ReleaseTag."
    }

    $CompanionCommit = Resolve-GitHubTagCommit `
        -CliPath $CliPath `
        -Repo $Repo `
        -ReleaseTag $ReleaseTag
    if ($CompanionCommit -notmatch '^[0-9a-f]{40}$' -or [string]$Manifest.commit -cne $CompanionCommit) {
        throw "Paired companion release manifest commit does not match the immutable companion tag."
    }

    $AddonCommit = Resolve-GitHubTagCommit `
        -CliPath $CliPath `
        -Repo "Antrakt92/ApplicantScout-Addon" `
        -ReleaseTag $AddonTag
    $CheckoutCommit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $CheckoutCommit -notmatch '^[0-9a-f]{40}$') {
        throw "Could not resolve the addon release checkout commit."
    }
    if ($AddonCommit -cne $CheckoutCommit) {
        throw "Remote addon tag $AddonTag moved away from the release checkout commit."
    }
    if ([string]$Manifest.pairedAddonTag -cne $AddonTag -or
        [string]$Manifest.pairedAddonCommit -cne $AddonCommit) {
        throw "Paired companion release manifest does not bind to addon $AddonTag at $AddonCommit."
    }

    $ManifestFiles = @($Manifest.files)
    if ($ManifestFiles.Count -ne $ExpectedPayloadAssets.Count) {
        throw "Paired companion release manifest file count does not match the published payload contract."
    }
    $SeenNames = @{}
    foreach ($File in $ManifestFiles) {
        $Name = [string]$File.name
        if ($ExpectedPayloadAssets -cnotcontains $Name -or $SeenNames.ContainsKey($Name)) {
            throw "Paired companion release manifest contains an unexpected or duplicate file: $Name"
        }
        $SeenNames[$Name] = $true
        if ($File.size -isnot [long] -and $File.size -isnot [int]) {
            throw "Paired companion release manifest size for $Name must be an integer."
        }
        if ([long]$File.size -lt 1 -or [string]$File.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Paired companion release manifest has invalid size or SHA-256 for $Name."
        }
        $MatchingAssets = @($Assets | Where-Object { $_.name -ceq $Name })
        if ($MatchingAssets.Count -ne 1) {
            throw "Published companion release does not contain exactly one payload asset named $Name."
        }
        $ReleaseAsset = $MatchingAssets[0]
        if ([long]$ReleaseAsset.size -ne [long]$File.size -or
            [string]$ReleaseAsset.digest -cne "sha256:$($File.sha256)") {
            throw "Published companion asset metadata does not match its immutable manifest: $Name"
        }
    }
    foreach ($ExpectedName in $ExpectedPayloadAssets) {
        if (-not $SeenNames.ContainsKey($ExpectedName)) {
            throw "Paired companion release manifest is missing payload file: $ExpectedName"
        }
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
$Readme = Get-Content -LiteralPath (Join-Path $RepoRoot "README.md") -Raw -Encoding UTF8

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
$Errors += Assert-PublicInstallLinksUseLatest `
    -Name "README.md" `
    -Text $Readme `
    -RequiredLatestUrls @(
        "https://github.com/Antrakt92/ApplicantScout-Addon/releases/latest",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest"
    )

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
    $ExpectedCompanionPayloadAssets = @(
        "ApplicantScoutCompanionSetup-$PairedCompanionVersion.exe",
        "ApplicantScoutCompanionSetup-$PairedCompanionVersion.exe.sha256",
        "ApplicantScoutCompanion-$PairedCompanionVersion-portable.zip"
    )
    $CompanionManifestName = "ApplicantScoutCompanion-$PairedCompanionVersion-release-manifest.json"
    $ExpectedCompanionAssets = @($ExpectedCompanionPayloadAssets) + @($CompanionManifestName)
    $ProtectedCompanionAssetPatterns = @(
        '^ApplicantScoutCompanionSetup-\d+\.\d+\.\d+\.exe$',
        '^ApplicantScoutCompanionSetup-\d+\.\d+\.\d+\.exe\.sha256$',
        '^ApplicantScoutCompanion-\d+\.\d+\.\d+-portable\.zip$',
        '^ApplicantScoutCompanion-\d+\.\d+\.\d+-release-manifest\.json$'
    )
    $PublishedCompanionRelease = Wait-GitHubReleaseAssets `
        -CliPath $GitHubCliPath `
        -Repo "Antrakt92/ApplicantScout-Companion" `
        -ReleaseTag $PairedCompanionTag `
        -ExpectedAssets $ExpectedCompanionAssets `
        -ProtectedAssetPatterns $ProtectedCompanionAssetPatterns `
        -WaitSeconds $PublishedReleaseWaitSeconds `
        -PollSeconds $PublishedReleasePollSeconds
    Test-PublishedCompanionManifest `
        -CliPath $GitHubCliPath `
        -Release $PublishedCompanionRelease `
        -Repo "Antrakt92/ApplicantScout-Companion" `
        -ReleaseTag $PairedCompanionTag `
        -ManifestName $CompanionManifestName `
        -ExpectedPayloadAssets $ExpectedCompanionPayloadAssets `
        -AddonTag "v$TagVersion"
}

Write-Host "Release version check passed: $TagName -> $TagVersion"
Write-Host "Expected paired companion ref: v$PairedCompanionVersion"
