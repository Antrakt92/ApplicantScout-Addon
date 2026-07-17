param(
    [string]$LuaLanguageServer = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ConfigPath = Join-Path $PSScriptRoot "lua-diagnostics.luarc.json"
$LocksPath = Join-Path $PSScriptRoot "tool-version-locks.json"
$LuaPath = Join-Path $RepoRoot "ApplicantScout.lua"
$TypesPath = Join-Path $PSScriptRoot "types\wow-globals.d.lua"

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $Output = @(& $FilePath @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    return @{
        ExitCode = $ExitCode
        Output = $Output
    }
}

function Assert-LuaDiagnosticsClean {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result
    )

    $Result.Output | ForEach-Object { Write-Host $_ }
    $JoinedOutput = $Result.Output -join "`n"
    if (
        $JoinedOutput -match "Diagnosis complete(?:d)?,\s+([1-9]\d*) problems? found" -or
        $JoinedOutput -match "Found\s+([1-9]\d*) problems?"
    ) {
        throw "lua-language-server reported $($Matches[1]) diagnostic problem(s)."
    }
    if ($Result.ExitCode -ne 0) {
        throw "lua-language-server exited with code $($Result.ExitCode)."
    }
    if ($JoinedOutput -notmatch "Diagnosis complete(?:d)?,\s+(?:no|0) problems? found") {
        throw "lua-language-server did not report a successful zero-diagnostic result."
    }
}

function Assert-LuaDiagnosticsSensitive {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedGlobal
    )

    $JoinedOutput = $Result.Output -join "`n"
    if (
        $Result.ExitCode -eq 0 -or
        $JoinedOutput -notmatch [regex]::Escape($ExpectedGlobal) -or
        $JoinedOutput -notmatch "undefined-global" -or
        (
            $JoinedOutput -notmatch "Diagnosis complete(?:d)?,\s+([1-9]\d*) problems? found" -and
            $JoinedOutput -notmatch "Found\s+([1-9]\d*) problems?"
        )
    ) {
        $Result.Output | ForEach-Object { Write-Host $_ }
        throw "lua-language-server did not detect the intentional undefined global '$ExpectedGlobal'."
    }
}

foreach ($RequiredPath in @($ConfigPath, $LocksPath, $LuaPath, $TypesPath)) {
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Missing Lua diagnostics input: $RequiredPath"
    }
}

if (-not $LuaLanguageServer) {
    $Command = Get-Command "lua-language-server" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($Command) {
        $LuaLanguageServer = $Command.Source
    }
}
if (-not $LuaLanguageServer -or -not (Test-Path -LiteralPath $LuaLanguageServer -PathType Leaf)) {
    throw "Missing lua-language-server. Pass -LuaLanguageServer with the pinned executable path."
}
$LuaLanguageServer = (Resolve-Path -LiteralPath $LuaLanguageServer).Path

$Locks = Get-Content -LiteralPath $LocksPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ExpectedVersion = [string]$Locks.luaLanguageServer.version
if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Malformed LuaLS version lock: $ExpectedVersion"
}
$VersionResult = Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @("--version")
$ActualVersion = ($VersionResult.Output -join "`n").Trim()
$ExpectedVersionPattern = "^$([regex]::Escape($ExpectedVersion))(?:-dev)?$"
if ($VersionResult.ExitCode -ne 0 -or $ActualVersion -notmatch $ExpectedVersionPattern) {
    throw "lua-language-server version is '$ActualVersion', expected $ExpectedVersion or $ExpectedVersion-dev."
}

$RunId = [System.Guid]::NewGuid().ToString("N")
$WorkspacePath = Join-Path ([System.IO.Path]::GetTempPath()) (
    "applicantscout-luals-workspace-" + $RunId
)
$LogRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "applicantscout-luals-log-" + $RunId
)
try {
    New-Item -ItemType Directory -Path $WorkspacePath | Out-Null
    Copy-Item -LiteralPath $LuaPath -Destination (Join-Path $WorkspacePath "ApplicantScout.lua")
    Copy-Item -LiteralPath $TypesPath -Destination (Join-Path $WorkspacePath "wow-globals.d.lua")

    $CleanResult = Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @(
        "--check=$WorkspacePath",
        "--check_format=pretty",
        "--checklevel=Warning",
        "--configpath=$ConfigPath",
        "--logpath=$(Join-Path $LogRoot 'clean')"
    )
    Assert-LuaDiagnosticsClean -Result $CleanResult

    $SensitivityGlobal = "ApplicantScoutIntentionalUndefinedGlobal"
    $SensitivityPath = Join-Path $WorkspacePath "diagnostic-sensitivity.lua"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $SensitivityPath,
        "$SensitivityGlobal()`n",
        $Utf8NoBom
    )
    $SensitivityResult = Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @(
        "--check=$WorkspacePath",
        "--check_format=pretty",
        "--checklevel=Warning",
        "--configpath=$ConfigPath",
        "--logpath=$(Join-Path $LogRoot 'sensitivity')"
    )
    Assert-LuaDiagnosticsSensitive `
        -Result $SensitivityResult `
        -ExpectedGlobal $SensitivityGlobal
    Write-Host "LuaLS sensitivity check detected the intentional undefined global."

    Remove-Item -LiteralPath $SensitivityPath -Force
    $FinalResult = Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @(
        "--check=$WorkspacePath",
        "--check_format=pretty",
        "--checklevel=Warning",
        "--configpath=$ConfigPath",
        "--logpath=$(Join-Path $LogRoot 'final')"
    )
    Assert-LuaDiagnosticsClean -Result $FinalResult
}
finally {
    Remove-Item -LiteralPath $WorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $LogRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "ApplicantScout LuaLS diagnostics passed with $ActualVersion."
