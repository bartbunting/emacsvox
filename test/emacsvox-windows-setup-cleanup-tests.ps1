# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'utils\emacsvox-windows-common.ps1')
. (Join-Path $repo 'utils\emacsvox-windows-setup-cleanup.ps1')
$testRoot = Join-Path $env:TEMP ('evox cleanup test ' + [guid]::NewGuid().ToString('N'))
$InstallRoot = Join-Path $testRoot 'installation'
$ResultFile = Join-Path $testRoot 'result.txt'
$product = 'Emacsvox.Native.Development.1'
$oldRoot = $env:OMNIVOX_VOICE_ROOT
$env:OMNIVOX_VOICE_ROOT = Join-Path $testRoot 'shared voices'
$Action = 'Cleanup'
$RemoveLogs = $false; $RemoveProfile = $false; $RemoveVoices = $false
try {
    foreach ($name in @('logs','Cache','profile','voices')) {
        $directory = Join-Path $InstallRoot $name
        New-Item -ItemType Directory -Force $directory | Out-Null
        [IO.File]::WriteAllText((Join-Path $directory 'keep.txt'), $name)
    }
    Write-EmacsvoxJson (Join-Path $InstallRoot 'setup-owner.json') @{ Product=$product }
    Invoke-SetupCleanup
    foreach ($name in @('logs','Cache','profile','voices')) {
        if (-not (Test-Path (Join-Path $InstallRoot "$name\keep.txt"))) { throw "Default removed $name" }
    }
    $RemoveLogs = $true
    Invoke-SetupCleanup
    foreach ($name in @('logs','Cache')) {
        if (Test-Path (Join-Path $InstallRoot $name)) { throw "Selected $name was retained" }
    }
    if (-not (Test-Path (Join-Path $InstallRoot 'profile\keep.txt'))) { throw 'Log cleanup removed profile' }
    $RemoveLogs = $false; $RemoveProfile = $true
    # Junctions inside a selected category must retain the whole category.
    $outside = Join-Path $testRoot 'outside'
    New-Item -ItemType Directory $outside | Out-Null
    [IO.File]::WriteAllText((Join-Path $outside 'outside.txt'), 'do not touch')
    $junction = Join-Path $InstallRoot 'profile\junction'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Invoke-SetupCleanup
    if (-not (Test-Path (Join-Path $outside 'outside.txt')) -or
        -not (Test-Path (Join-Path $InstallRoot 'profile\keep.txt'))) { throw 'Cleanup crossed a junction' }
    if ([IO.File]::ReadAllText($ResultFile) -notmatch 'junction') { throw 'Missing retained-data explanation' }
    [IO.Directory]::Delete($junction)
    Invoke-SetupCleanup
    if (Test-Path (Join-Path $InstallRoot 'profile')) { throw 'Selected profile retained' }
    if (-not (Test-Path (Join-Path $InstallRoot 'voices\keep.txt'))) { throw 'Unowned voice folder was removed' }
    # No voice root is created by review when none exists.
    $Action = 'CleanupReview'
    Invoke-SetupCleanup
    if (Test-Path $env:OMNIVOX_VOICE_ROOT) { throw 'Review initialized an absent voice library' }
    # The provider decides removal, with a fresh hash between packages.
    New-Item -ItemType Directory $env:OMNIVOX_VOICE_ROOT | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:OMNIVOX_VOICE_ROOT 'host.json'), '{}')
    $script:requests = @(); $script:inspections = 0
    function Open-VoiceCleanupService {
        $p = [pscustomobject]@{ HasExited=$true }
        $p | Add-Member ScriptMethod Dispose {}
        return $p
    }
    function Invoke-VoiceCleanupRequest($Process, [hashtable]$Request) {
        $script:requests += $Request
        switch ($Request.command) {
            host { return @{ removal_version=1; root=$env:OMNIVOX_VOICE_ROOT } }
            inspect {
                $script:inspections++
                return @{ sha256="hash$script:inspections"; index=@{
                    packages=@(@{ownership='managed';package_id='a';revision_id='1';files=@(@{bytes=25})},
                               @{ownership='managed';package_id='b';revision_id='1';files=@(@{bytes=25})},
                               @{ownership='imported';package_id='c';revision_id='1';files=@(@{bytes=25})})
                    voices=@(@{package_id='a';revision_id='1';engine_id='flite';physical_id='safe';display_name='Safe'},
                             @{package_id='b';revision_id='1';engine_id='piper';physical_id='busy';display_name='Busy'})
                } }
            }
            uninstall-preview {
                if ($Request.expected_sha256 -ne "hash$script:inspections") { throw 'Stale index passed' }
                return @{review=@{blockers=$(if ($Request.voice -eq 'busy') {@('Active generation')} else {@()});operation_id='op';plan_sha256='plan'}}
            }
            uninstall {
                if ($Request.expected_sha256 -ne 'plan') { throw 'Removal omitted reviewed plan hash' }
                return @{result=@{status='complete';removed_bytes=25;remaining_bytes=0;detail='Done'}}
            }
            default { throw "Unexpected command: $($Request.command)" }
        }
    }
    $report = @(Invoke-VoiceCleanup $true) -join "`n"
    if (@($script:requests | Where-Object {$_.command -eq 'uninstall'}).Count -ne 1 -or
        $report -notmatch 'Kept Busy: Active generation' -or $report -notmatch 'Safe: complete') {
        throw 'Voice cleanup did not honor native retention'
    }
    Write-Host 'PASS: preservation defaults, scoped cleanup, junction refusal, absent library, native removal review and retained voices.'
}
finally {
    $env:OMNIVOX_VOICE_ROOT = $oldRoot
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'profile\junction')) { [IO.Directory]::Delete((Join-Path $InstallRoot 'profile\junction')) }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
