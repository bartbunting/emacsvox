# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'utils\emacsvox-windows-common.ps1')
$testRoot = Join-Path $env:TEMP ('evox setup unit ' + [guid]::NewGuid().ToString('N').Substring(0,12))
$installation = Join-Path $testRoot 'install with spaces'
$manifestPath = Join-Path $testRoot 'manifest.json'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$helper = Join-Path $repo 'utils\emacsvox-windows-setup-helper.ps1'
$product = 'Emacsvox.Native.Development.1'
New-Item -ItemType Directory $testRoot | Out-Null
function Invoke-Preflight([string]$Expected = '') {
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper,
                   '-Action','Preflight','-InstallRoot',$installation,'-Manifest',$manifestPath)
    try {
        Invoke-EmacsvoxNative $powershell $arguments @{ EMACS=$null } | Out-Null
        if ($Expected) { throw "Expected failure: $Expected" }
    }
    catch {
        $message = $_.Exception.Message -replace '\s+', ' '
        if (-not $Expected -or $message -notlike "*$Expected*" -or
            $_.Exception.Message -like 'Expected failure:*') { throw }
    }
}
try {
    $file = 'Launcher/Start.ps1'
    $payload = Join-Path $installation $file
    $reference = Join-Path $testRoot 'reference.ps1'
    [IO.File]::WriteAllText($reference, '# first version')
    $hash = (Get-FileHash $reference).Hash.ToLowerInvariant()
    $manifest = @{ Schema=1; Product=$product; Build='2026.9.5-dev-0123456789abcdef'; Files=@(@{Path=$file; SHA256=$hash}) }
    Write-EmacsvoxJson $manifestPath $manifest
    Invoke-Preflight
    if (Test-Path $installation) { throw 'Preflight changed destination' }
    New-Item -ItemType Directory -Force (Split-Path $payload) | Out-Null
    Copy-Item $reference $payload
    Invoke-Preflight 'not managed'
    Write-EmacsvoxJson (Join-Path $installation 'setup-owner.json') @{ Schema=1; Product=$product }
    Invoke-Preflight 'not owned by Setup'
    $history = Join-Path $installation 'Manifests'
    New-Item -ItemType Directory $history | Out-Null
    Write-EmacsvoxJson (Join-Path $history 'previous.json') $manifest
    Invoke-Preflight
    # Upgrade may replace an unmodified file owned by the previous version.
    $manifest.Files[0].SHA256 = '0' * 64
    Write-EmacsvoxJson $manifestPath $manifest
    Invoke-Preflight
    [IO.File]::WriteAllText($payload, '# user edit')
    Invoke-Preflight 'has been changed'
    if ([IO.File]::ReadAllText($payload) -ne '# user edit') { throw 'Preflight overwrote local edit' }
    # Missing owned files can be repaired.
    Remove-Item -LiteralPath $payload
    Invoke-Preflight
    $manifest.Files[0].Path = '../outside'
    Write-EmacsvoxJson $manifestPath $manifest
    Invoke-Preflight 'Invalid setup file manifest'
    # Exercise actual command dispatch, not only the dot-sourced functions.
    $report = Join-Path $testRoot 'cleanup-report.txt'
    $logDirectory = Join-Path $installation 'logs'
    New-Item -ItemType Directory $logDirectory | Out-Null
    [IO.File]::WriteAllText((Join-Path $logDirectory 'fixture.log'), 'owned log')
    foreach ($action in @('UninstallCheck','CleanupReview','Cleanup')) {
        $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$helper,
            '-Action',$action,'-InstallRoot',$installation,'-ResultFile',$report)
        Invoke-EmacsvoxNative $powershell $arguments @{OMNIVOX_VOICE_ROOT=(Join-Path $testRoot 'absent voices')} | Out-Null
        if (-not (Test-Path (Join-Path $logDirectory 'fixture.log'))) { throw 'Default helper cleanup deleted data' }
        if ($action -ne 'UninstallCheck' -and -not (Test-Path $report)) { throw "Missing $action report" }
    }
    Invoke-EmacsvoxNative $powershell ($arguments + '-RemoveLogs') | Out-Null
    if (Test-Path $logDirectory) { throw 'Helper did not dispatch selected cleanup' }
    Write-Host 'PASS: setup preflight, ownership, upgrade, missing-file repair and edited-source protection.'
}
finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
