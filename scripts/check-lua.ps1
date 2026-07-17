param(
    [string]$LuaLanguageServer = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ConfigPath = Join-Path $PSScriptRoot "lua-diagnostics.luarc.json"
$LocksPath = Join-Path $PSScriptRoot "tool-version-locks.json"
$LuaPath = Join-Path $RepoRoot "ApplicantScout.lua"

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

foreach ($RequiredPath in @($ConfigPath, $LocksPath, $LuaPath)) {
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

$LogPath = Join-Path ([System.IO.Path]::GetTempPath()) (
    "applicantscout-luals-" + [System.Guid]::NewGuid().ToString("N")
)
try {
    $Result = Invoke-NativeCapture -FilePath $LuaLanguageServer -Arguments @(
        "--check=$LuaPath",
        "--check_format=pretty",
        "--checklevel=Warning",
        "--configpath=$ConfigPath",
        "--logpath=$LogPath"
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
finally {
    Remove-Item -LiteralPath $LogPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "ApplicantScout LuaLS diagnostics passed with $ActualVersion."
