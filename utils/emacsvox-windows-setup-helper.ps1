# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Preflight','Configure','Activate','UninstallCheck','CleanupReview','Cleanup')][string]$Action,
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [string]$Manifest,
    [string]$ErrorFile,
    [string]$ResultFile,
    [switch]$RemoveLogs,
    [switch]$RemoveProfile,
    [switch]$RemoveVoices
)
. (Join-Path $PSScriptRoot 'emacsvox-windows-common.ps1')
$product = 'Emacsvox.Native.Development.1'
function Read-SetupManifest([string]$Path) {
    $data = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    if ($data.Schema -ne 1 -or $data.Product -ne $product -or
        $data.Build -notmatch '^\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}$') { throw 'Unrecognized setup manifest.' }
    $seen = @{}
    foreach ($file in $data.Files) {
        if ($file.Path -notmatch '^(Applications|Emacs|Omnivox|Launcher|Setup)/[^/]' -or
            $file.Path -match '(^|/)\.\.?(/|$)|[\\:\r\n]' -or $file.Path.Contains('//') -or
            $file.SHA256 -notmatch '^[a-f0-9]{64}$' -or $seen.ContainsKey($file.Path)) {
            throw 'Invalid setup file manifest.'
        }
        $seen[$file.Path] = $true
    }
    return $data
}
function Remove-PreviousSetupShortcuts {
    $shell = New-Object -ComObject WScript.Shell
    $oldGroup = Join-Path ([Environment]::GetFolderPath('Programs')) 'Emacsvox Windows Development'
    $links = @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Emacsvox Windows Development.lnk'))
    foreach ($name in @('Emacsvox Windows Development','Check speech','Uninstall Emacsvox Windows Development')) {
        $links += Join-Path $oldGroup "$name.lnk"
    }
    foreach ($path in $links) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $link = $shell.CreateShortcut($path)
        $launcher = Join-Path $InstallRoot 'Launcher\Start.ps1'
        $launchOwned = $link.TargetPath -eq (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -and
            $link.Arguments.IndexOf(('"' + $launcher + '"'), [StringComparison]::OrdinalIgnoreCase) -ge 0
        $uninstallOwned = (Split-Path $link.TargetPath -Parent) -eq $InstallRoot -and
            (Split-Path $link.TargetPath -Leaf) -match '^unins\d+[.]exe$'
        if ($launchOwned -or $uninstallOwned) { Remove-Item -LiteralPath $path -Force }
    }
    if ((Test-Path -LiteralPath $oldGroup) -and -not @(Get-ChildItem -LiteralPath $oldGroup -Force).Count) {
        [IO.Directory]::Delete($oldGroup, $false)
    }
}
function Assert-NotRunning {
    $prefix = $InstallRoot.TrimEnd('\') + '\'
    foreach ($process in Get-CimInstance Win32_Process) {
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            $process.Name -notmatch '^unins\d+[.]exe$') {
            throw "Close the Emacsvox application using this installation, then try again. Running: $($process.Name) (process $($process.ProcessId))."
        }
    }
}
try {
    Assert-NativeWindows
    Assert-WindowsLocalPath $InstallRoot
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    # Do not follow a junction into another installation during repair/removal.
    $ancestor = $InstallRoot
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and
            ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Choose an installation directory without junctions or symbolic links.'
        }
        $ancestor = Split-Path $ancestor -Parent
    }
    Assert-NotRunning
    if ($Action -eq 'UninstallCheck') { exit 0 }
    if ($Action -in @('CleanupReview','Cleanup')) {
        . (Join-Path $PSScriptRoot 'emacsvox-windows-setup-cleanup.ps1')
        Invoke-SetupCleanup
        exit 0
    }
    if ($env:EMACS) { throw 'EMACS selects another Emacs. Unset it before installing the bundled desktop.' }
    $data = Read-SetupManifest $Manifest
    $application = Join-Path $InstallRoot "Applications\$($data.Build)"
    if ($Action -eq 'Preflight') {
        $owner = Join-Path $InstallRoot 'setup-owner.json'
        $known = @{}
        if (Test-Path -LiteralPath $InstallRoot) {
            if (Test-Path -LiteralPath $owner) {
                if (([IO.File]::ReadAllText($owner) | ConvertFrom-Json).Product -ne $product) {
                    throw 'This directory belongs to another installation. Choose a different destination.'
                }
                $manifests = Join-Path $InstallRoot 'Manifests'
                if (Test-Path -LiteralPath $manifests) {
                    foreach ($record in Get-ChildItem -LiteralPath $manifests -Filter '*.json' -File) {
                        foreach ($file in (Read-SetupManifest $record.FullName).Files) {
                            if (-not $known.ContainsKey($file.Path)) { $known[$file.Path] = @() }
                            $known[$file.Path] += $file.SHA256
                        }
                    }
                }
            }
            elseif (@(Get-ChildItem -LiteralPath $InstallRoot -Force).Count) {
                throw 'This directory is not managed by Emacsvox Setup. Choose an empty destination.'
            }
        }
        foreach ($file in $data.Files) {
            $path = Join-Path $InstallRoot $file.Path
            if ($path.Length -ge 248) { throw 'The installation path is too long. Choose a shorter destination.' }
            if (Test-Path -LiteralPath $path) {
                if (-not $known.ContainsKey($file.Path) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -notin $known[$file.Path]) {
                    throw "An installed file has been changed or is not owned by Setup: $path. Preserve your changes and choose another destination."
                }
            }
        }
        exit 0
    }
    if ($Action -eq 'Configure') {
        # Inno has installed the verified complete runtimes and their receipt.
        # The existing installer now validates them and builds native byte-code.
        & (Join-Path $application 'bin\emacsvox-install.ps1') -DownloadEmacs -Offline `
            -InstallRoot $InstallRoot -CacheDirectory (Join-Path $InstallRoot 'Cache') -NoAudioCheck
        exit 0
    }
    if (-not (Test-Path -LiteralPath (Join-Path $application 'native-install.json'))) {
        throw 'The new application has not completed configuration.'
    }
    Write-EmacsvoxJson (Join-Path $InstallRoot 'current.json') @{ Schema=1; Product=$product; Build=$data.Build }
    try { Remove-PreviousSetupShortcuts }
    catch { Write-Warning "Emacsvox is active; an old shortcut could not be removed: $($_.Exception.Message)" }
}
catch {
    $message = $_.Exception.Message
    if ($ErrorFile) { [IO.File]::WriteAllText($ErrorFile, $message, (New-Object Text.UTF8Encoding($false))) }
    Write-Error $message -ErrorAction Continue
    exit 1
}
