# Manifold release: build + stage to ~\Manifold + refresh Desktop shortcut.
# Threads channel/version/sha/manifest-base into the binary as dart-defines so
# BuildInfo can identify itself at runtime.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File apps\desktop-flutter\tools\release.ps1
#   powershell -ExecutionPolicy Bypass -File apps\desktop-flutter\tools\release.ps1 -Channel beta
#
# -Channel : dev | beta | stable     (default: beta)
# -BaseUrl : update manifest base    (overrides MANIFOLD_UPDATE_BASE_URL env)

param(
    [ValidateSet('dev','beta','stable')]
    [string]$Channel = 'beta',
    [string]$BaseUrl = $env:MANIFOLD_UPDATE_BASE_URL
)

$ErrorActionPreference = 'Stop'

$flutterDir = Split-Path -Parent $PSScriptRoot
$installDir = Join-Path $env:USERPROFILE 'Manifold'
$exeName    = 'git_desktop.exe'

function Get-PubspecVersion {
    $pubspec = Join-Path $flutterDir 'pubspec.yaml'
    $line = Select-String -Path $pubspec -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if (-not $line) { throw "Could not read version from $pubspec" }
    $raw = $line.Matches[0].Groups[1].Value.Trim()
    # Strip the +build suffix; semver-2.0 build metadata is informational.
    return ($raw -split '\+')[0]
}

function Get-GitSha {
    try {
        $sha = git -C $flutterDir rev-parse --short=7 HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) { return $sha.Trim() }
    } catch {}
    return ''
}

Push-Location $flutterDir
try {
    $version = Get-PubspecVersion
    $sha     = Get-GitSha
    Write-Host "==> manifold $version ($Channel)$(if ($sha) { ' '+$sha })" -ForegroundColor Cyan

    # If a previous build is currently running, the staged exe is locked
    # by the OS and the staging step (robocopy /MIR) would hang on retry.
    # Close it cleanly up front so the user gets a fast, deterministic build.
    $running = Get-Process git_desktop -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "==> closing running Manifold instance(s) so staging can write" -ForegroundColor Cyan
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    $defines = @(
        "--dart-define=MANIFOLD_CHANNEL=$Channel",
        "--dart-define=MANIFOLD_VERSION=$version"
    )
    if ($sha)     { $defines += "--dart-define=MANIFOLD_GIT_SHA=$sha" }
    if ($BaseUrl) { $defines += "--dart-define=MANIFOLD_UPDATE_BASE_URL=$BaseUrl" }

    Write-Host "==> flutter build windows --release $($defines -join ' ')" -ForegroundColor Cyan
    & flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

    $releaseDir = Join-Path $flutterDir 'build\windows\x64\runner\Release'
    if (-not (Test-Path $releaseDir)) { throw "Release output missing: $releaseDir" }

    Write-Host "==> staging $installDir" -ForegroundColor Cyan
    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }
    # Mirror so removed plugins/data files don't pile up across builds.
    # /R:3 /W:1 puts a tight ceiling on retries (robocopy's defaults are
    # /R:1000000 /W:30, ~indefinite on a locked file) — better to fail
    # loudly than silently hang for hours.
    robocopy $releaseDir $installDir /MIR /R:3 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

    $exePath = Join-Path $installDir $exeName
    $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Manifold.lnk'
    Write-Host "==> refreshing $lnkPath" -ForegroundColor Cyan
    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($lnkPath)
    $sc.TargetPath       = $exePath
    $sc.WorkingDirectory = $installDir
    $sc.IconLocation     = "$exePath,0"
    $sc.Description      = "Manifold Git Client ($Channel $version)"
    $sc.Save()

    Write-Host "==> done" -ForegroundColor Green
    Write-Host "    channel : $Channel"
    Write-Host "    version : $version"
    if ($sha) { Write-Host "    sha     : $sha" }
    Write-Host "    exe     : $exePath"
    Write-Host "    lnk     : $lnkPath"
}
finally {
    Pop-Location
}
