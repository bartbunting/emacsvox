# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Setup,
    [string]$Upgrade,
    [string]$FailedUpgrade,
    [switch]$AudioCheck
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
$registration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B2C8A798-1699-456B-8A64-A6D02C347972}_is1'
if (Test-Path $registration) { throw 'A development Setup installation is already registered; preserve it and test in another Windows account.' }
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Emacsvox Windows Development.lnk'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Emacsvox Windows Development'
if ((Test-Path $desktop) -or (Test-Path $menu)) { throw 'Existing development shortcuts would be changed; use another test account.' }
$work = Join-Path $env:TEMP ('evox setup test ' + [guid]::NewGuid().ToString('N').Substring(0,12))
$installation = Join-Path $work 'installed desktop'
New-Item -ItemType Directory $work | Out-Null
$oldEmacs = $env:EMACS
$oldPath = $env:PATH
$passed = $false
$running = $null
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Check-Launcher([switch]$Speech) {
    $mode = if ($Speech) { '-Check' } else { '-Diagnose' }
    Invoke-EmacsvoxNative $powershell @('-NoProfile','-ExecutionPolicy','Bypass','-File',
        (Join-Path $installation 'Launcher\Start.ps1'), $mode) -TimeoutSeconds 180 | Write-Host
}
function Run-Setup([string]$Program, [string]$Log, [switch]$ExpectFailure) {
    $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR=' + $installation),
                   '/TASKS=desktopicon',('/LOG=' + (Join-Path $work $Log)))
    if ($ExpectFailure) {
        try { Invoke-EmacsvoxNative $Program $arguments -TimeoutSeconds 900 | Out-Null }
        catch { return }
        throw 'Expected setup to fail'
    }
    Invoke-EmacsvoxNative $Program $arguments -TimeoutSeconds 900 | Out-Null
}
try {
    Remove-Item Env:EMACS -ErrorAction SilentlyContinue
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    Run-Setup $Setup 'first-install.log'
    if (-not (Test-Path $registration) -or -not (Test-Path $desktop) -or -not (Test-Path $menu)) {
        throw 'Setup did not register the per-user installation and shortcuts'
    }
    $currentPath = Join-Path $installation 'current.json'
    $first = [IO.File]::ReadAllText($currentPath) | ConvertFrom-Json
    $application = Join-Path $installation "Applications\$($first.Build)"
    $config = [IO.File]::ReadAllText((Join-Path $application 'native-install.json')) | ConvertFrom-Json
    $profile = Join-Path $config.Profile 'preserved-profile.txt'
    [IO.File]::WriteAllText($profile, 'profile survives setup and uninstall')
    $voices = Join-Path $installation 'voices'
    New-Item -ItemType Directory $voices | Out-Null
    $voice = Join-Path $voices 'preserved-voice.txt'
    [IO.File]::WriteAllText($voice, 'user voice stays')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($desktop)
    if ($shortcut.Arguments -notlike '*Launcher\Start.ps1*' -or $shortcut.TargetPath -notlike '*powershell.exe') {
        throw 'Desktop shortcut does not use the installed stable launcher'
    }
    # Test the actual shortcut target and arguments, selecting diagnostics to
    # avoid leaving an interactive Emacs running during subsequent tests.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $shortcut.TargetPath
    $start.Arguments = $shortcut.Arguments + ' -Diagnose'
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if (-not $process.WaitForExit(120000) -or $process.ExitCode -ne 0) { throw 'Shortcut launcher failed' }
    $process.Dispose()
    $start.FileName = $config.Emacs
    $start.Arguments = (@('-Q','--batch','--eval','(sleep-for 180)') | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $running = [Diagnostics.Process]::Start($start)
    Run-Setup $Setup 'running-refused.log' -ExpectFailure
    if ($running.HasExited) { throw 'Setup closed the running Emacs' }
    $running.Kill(); $running.WaitForExit(); $running.Dispose(); $running = $null
    $missing = Join-Path $application 'lisp\emacsvox-wizards.el'
    Remove-Item -LiteralPath $missing
    Run-Setup $Setup 'repair.log'
    if (-not (Test-Path $missing) -or [IO.File]::ReadAllText($profile) -ne 'profile survives setup and uninstall') {
        throw 'Repair failed or changed the profile'
    }
    if ($FailedUpgrade) {
        $previous = [IO.File]::ReadAllText($currentPath)
        Run-Setup $FailedUpgrade 'failed-upgrade.log' -ExpectFailure
        if ([IO.File]::ReadAllText($currentPath) -ne $previous) { throw 'Failed upgrade changed the working selection' }
        Check-Launcher
    }
    if ($Upgrade) {
        Run-Setup $Upgrade 'upgrade.log'
        $current = [IO.File]::ReadAllText($currentPath) | ConvertFrom-Json
        if ($current.Build -eq $first.Build -or [IO.File]::ReadAllText($profile) -ne 'profile survives setup and uninstall') {
            throw 'Upgrade did not activate a different build with the same profile'
        }
    }
    Check-Launcher
    if ($AudioCheck) { Check-Launcher -Speech }
    $uninstaller = Join-Path $installation 'unins000.exe'
    Invoke-EmacsvoxNative $uninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG=' + (Join-Path $work 'uninstall.log'))) -TimeoutSeconds 180 | Out-Null
    if ((Test-Path $registration) -or (Test-Path $desktop) -or (Test-Path $menu) -or (Test-Path $currentPath)) {
        throw 'Uninstall left registration, shortcuts or the active selection behind'
    }
    if ([IO.File]::ReadAllText($profile) -ne 'profile survives setup and uninstall' -or
        [IO.File]::ReadAllText($voice) -ne 'user voice stays') { throw 'Uninstall removed user data' }
    foreach ($directory in @('Applications','Emacs','Omnivox','Launcher','Setup','Manifests')) {
        $path = Join-Path $installation $directory
        if ((Test-Path $path) -and @(Get-ChildItem -LiteralPath $path -File -Recurse).Count) {
            throw "Uninstall left application files in $path"
        }
    }
    $passed = $true
    Write-Host 'PASS: per-user Setup, shortcuts, busy-install refusal, repair and uninstall with user data preserved.'
    if ($Upgrade) { Write-Host 'PASS: upgrade activated a different build and preserved the profile.' }
    else { Write-Host 'Upgrade acceptance was skipped; pass a second build with -Upgrade.' }
    if ($FailedUpgrade) { Write-Host 'PASS: failed upgrade preserved the previous working selection and launcher.' }
}
finally {
    if ($running) { if (-not $running.HasExited) { $running.Kill(); $running.WaitForExit() }; $running.Dispose() }
    $env:PATH = $oldPath
    if ($null -eq $oldEmacs) { Remove-Item Env:EMACS -ErrorAction SilentlyContinue } else { $env:EMACS = $oldEmacs }
    Write-Host "Retained setup acceptance logs: $work"
    if (-not $passed) { Write-Host 'The isolated test installation was retained for diagnosis.' }
}
