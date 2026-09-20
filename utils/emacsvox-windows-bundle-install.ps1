# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Emacsvox\Native",
    [switch]$Check,
    [switch]$NoAudioCheck
)
. (Join-Path $PSScriptRoot 'Source\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
Assert-WindowsLocalPath $PSScriptRoot
Assert-WindowsLocalPath $InstallRoot
if ($env:EMACS) { throw 'This bundle installs its pinned Emacs. Unset EMACS or use the source installer with your explicit selection.' }
$manifestFile = Join-Path $PSScriptRoot 'bundle.json'
$manifest = [IO.File]::ReadAllText($manifestFile) | ConvertFrom-Json
if ($manifest.Schema -ne 1 -or $manifest.Build -notmatch '^\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}$') {
    throw 'Unsupported development bundle manifest.'
}
$seen = @{}
foreach ($file in $manifest.Files) {
    if ($file.Path -notmatch '^(Source/|Archives/|Install[.](ps1|cmd)$|README[.]txt$)' -or
        $file.Path -match '(^|/)\.\.?(/|$)|[\\:\r\n]' -or $file.SHA256 -notmatch '^[a-f0-9]{64}$' -or
        $seen.ContainsKey($file.Path)) { throw 'Invalid bundle file manifest.' }
    $seen[$file.Path] = $true
    $path = Join-Path $PSScriptRoot $file.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.SHA256) {
        throw "Bundle checksum mismatch: $($file.Path). Extract a fresh copy."
    }
}
$source = Join-Path $PSScriptRoot 'Source'
$cache = Join-Path $PSScriptRoot 'Archives'
$pins = Read-EmacsvoxPins (Join-Path $source 'etc\wsl-install.conf')
$windows = Read-EmacsvoxPins (Join-Path $source 'etc\windows-install.conf')
# Check both archives before copying application files, even on a repeat run.
Get-EmacsvoxArchive $windows.EMACSVOX_WINDOWS_EMACS_URL `
    (Join-Path $cache $windows.EMACSVOX_WINDOWS_EMACS_ARCHIVE) $windows.EMACSVOX_WINDOWS_EMACS_SHA256 -Offline | Out-Null
Get-EmacsvoxArchive "$($pins.EMACSVOX_WSL_OMNIVOX_RELEASE_URL)/$($pins.EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE)" `
    (Join-Path $cache $pins.EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE) $pins.EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256 -Offline | Out-Null
$application = Join-Path $InstallRoot "Applications\$($manifest.Build)"
$stage = Join-Path (Split-Path $application -Parent) ('.stage-' + [guid]::NewGuid().ToString('N'))
foreach ($file in $manifest.Files | Where-Object { $_.Path.StartsWith('Source/') }) {
    foreach ($directory in @($stage, $application)) {
        if ([IO.Path]::GetFullPath((Join-Path $directory $file.Path.Substring(7))).Length -ge 248) {
            throw 'Application paths are too long for Windows PowerShell 5.1. Choose a shorter -InstallRoot.'
        }
    }
}
$receipt = Join-Path $application 'bundle-receipt.json'
$manifestHash = (Get-FileHash -LiteralPath $manifestFile -Algorithm SHA256).Hash
if (Test-Path -LiteralPath $application) {
    if (-not (Test-Path -LiteralPath $receipt) -or
        ([IO.File]::ReadAllText($receipt) | ConvertFrom-Json).ManifestSHA256 -ne $manifestHash) {
        throw "Unmanaged or incomplete application directory: $application"
    }
    foreach ($file in $manifest.Files | Where-Object { $_.Path.StartsWith('Source/') }) {
        $installed = Join-Path $application $file.Path.Substring(7)
        if (-not (Test-Path -LiteralPath $installed -PathType Leaf) -or
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash -ine $file.SHA256) {
            throw "Installed sources have changed: $installed. Keep your changes and use another -InstallRoot."
        }
    }
}
Write-Host "Offline development bundle: $($manifest.Build)"
Write-Host "Application: $application"
if ($Check) {
    & (Join-Path $source 'bin\emacsvox-install.ps1') -DownloadEmacs -Offline -Check `
        -InstallRoot $InstallRoot -CacheDirectory $cache
    return
}
if (-not (Test-Path -LiteralPath $application)) {
    New-Item -ItemType Directory -Force (Split-Path $application -Parent) | Out-Null
    try {
        # Copy only files in the manifest; never import an added local config or
        # byte-code from the extracted bundle into the installed application.
        foreach ($file in $manifest.Files | Where-Object { $_.Path.StartsWith('Source/') }) {
            $target = Join-Path $stage $file.Path.Substring(7)
            New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file.Path) -Destination $target
        }
        Write-EmacsvoxJson (Join-Path $stage 'bundle-receipt.json') @{ Schema=1; ManifestSHA256=$manifestHash }
        [IO.Directory]::Move($stage, $application)
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
& (Join-Path $application 'bin\emacsvox-install.ps1') -DownloadEmacs -Offline `
    -InstallRoot $InstallRoot -CacheDirectory $cache -NoAudioCheck:$NoAudioCheck
Write-Host 'Start this installation with:'
Write-Host ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $application 'bin\emacsvox.ps1') + '"')
