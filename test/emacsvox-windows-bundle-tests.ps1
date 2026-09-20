# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BundleArchive,
    [switch]$AudioCheck,
    [switch]$KeepInstallation
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
$testRoot = Join-Path $env:TEMP ('evox offline test ' + [guid]::NewGuid().ToString('N').Substring(0,12))
$bundle = Join-Path $testRoot 'extracted bundle'
$installation = Join-Path $testRoot 'installed application'
$oldPath = $env:PATH
$oldEmacs = $env:EMACS
$passed = $false
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected rejection: $Message"
}
try {
    # The payload must run without Git, WSL, MSYS2 or an existing Emacs on PATH.
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    Remove-Item Env:EMACS -ErrorAction SilentlyContinue
    Expand-EmacsvoxZip $BundleArchive $bundle
    $installer = Join-Path $bundle 'Install.ps1'
    & $installer -Check -InstallRoot $installation
    if (Test-Path $installation) { throw 'Bundle doctor changed installation state' }
    $longRoot = Join-Path $testRoot ('long installation ' * 9)
    Assert-Rejected { & $installer -InstallRoot $longRoot -NoAudioCheck } 'paths are too long'
    if (Test-Path $longRoot) { throw 'Long path preflight changed installation state' }
    $manifest = [IO.File]::ReadAllText((Join-Path $bundle 'bundle.json')) | ConvertFrom-Json
    $archiveEntry = $manifest.Files | Where-Object { $_.Path.StartsWith('Archives/') } | Select-Object -First 1
    $archive = Join-Path $bundle $archiveEntry.Path
    Move-Item -LiteralPath $archive -Destination "$archive.saved"
    try {
        Assert-Rejected { & $installer -InstallRoot $installation -NoAudioCheck } 'Bundle checksum mismatch'
        [IO.File]::WriteAllText($archive, 'damaged download')
        Assert-Rejected { & $installer -InstallRoot $installation -NoAudioCheck } 'Bundle checksum mismatch'
        if (Test-Path $installation) { throw 'Damaged bundle changed installation state' }
    }
    finally {
        if (Test-Path $archive) { Remove-Item -LiteralPath $archive }
        Move-Item -LiteralPath "$archive.saved" -Destination $archive
    }
    $application = Join-Path $installation "Applications\$($manifest.Build)"
    New-Item -ItemType Directory -Force $application | Out-Null
    Assert-Rejected { & $installer -InstallRoot $installation -NoAudioCheck } 'Unmanaged or incomplete'
    Remove-Item -LiteralPath $application
    & $installer -InstallRoot $installation -NoAudioCheck
    $config = [IO.File]::ReadAllText((Join-Path $application 'native-install.json')) | ConvertFrom-Json
    if ($config.Emacs -notlike "$installation\Emacs\*" -or $config.Omnivox -notlike "$installation\Omnivox\*") {
        throw 'Bundle selected external developer runtimes'
    }
    $receipt = Join-Path (Split-Path (Split-Path $config.Emacs)) 'emacsvox-build.json'
    $receiptHash = (Get-FileHash $receipt).Hash
    $marker = Join-Path $config.Profile 'user-state-preserved.txt'
    [IO.File]::WriteAllText($marker, 'user data must survive repeat installation')
    & $installer -InstallRoot $installation -NoAudioCheck
    if ((Get-FileHash $receipt).Hash -ne $receiptHash -or
        [IO.File]::ReadAllText($marker) -ne 'user data must survive repeat installation') {
        throw 'Repeat installation changed runtime identity or user profile'
    }
    $source = Join-Path $application 'lisp\emacsvox-setup.el'
    $original = [IO.File]::ReadAllBytes($source)
    try {
        [IO.File]::AppendAllText($source, "`n; test local edit`n")
        Assert-Rejected { & $installer -InstallRoot $installation -NoAudioCheck } 'Installed sources have changed'
        if (-not [IO.File]::ReadAllText($source).Contains('; test local edit')) { throw 'Local source edit was overwritten' }
    }
    finally { [IO.File]::WriteAllBytes($source, $original) }
    # Restoring bytes changes the timestamp: rebuild before the launcher check.
    & $installer -InstallRoot $installation -NoAudioCheck
    & (Join-Path $application 'bin\emacsvox.ps1') -Diagnose
    if ($AudioCheck) { & (Join-Path $application 'bin\emacsvox.ps1') -Check }
    $passed = $true
    Write-Host 'PASS: offline bundle, fresh native runtimes, missing/corrupt inputs, repeat install, profile preservation and local-source protection.'
    if (-not $AudioCheck) { Write-Host 'Graphical/audio acceptance was skipped.' }
}
finally {
    $env:PATH = $oldPath
    if ($null -eq $oldEmacs) { Remove-Item Env:EMACS -ErrorAction SilentlyContinue }
    else { $env:EMACS = $oldEmacs }
    if ($KeepInstallation -or -not $passed) { Write-Host "Retained acceptance files: $testRoot" }
    elseif (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
