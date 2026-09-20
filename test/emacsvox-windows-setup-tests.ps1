# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Setup,
    [string]$Upgrade,
    [string]$FailedUpgrade,
    # Continue failure/recovery checks in this script's retained test fixture.
    [string]$ResumeAfterRepair,
    # Export only this test's logs for CI, including on acceptance failure.
    [string]$LogDirectory,
    [switch]$AudioCheck,
    [switch]$IsolatedIdentity
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
if ($LogDirectory) {
    $LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
    New-Item -ItemType Directory -Path $LogDirectory -ErrorAction Stop | Out-Null
}
$registration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B2C8A798-1699-456B-8A64-A6D02C347972}_is1'
if ($IsolatedIdentity) {
    foreach ($candidate in @($Setup,$Upgrade,$FailedUpgrade) | Where-Object { $_ }) {
        if ((Split-Path $candidate -Leaf) -notlike 'emacsvox-fixture-*-setup.exe') { throw 'Use a separately compiled fixture installer with IsolatedIdentity.' }
    }
    $registration = $registration.Replace('B2C8A798-1699-456B-8A64-A6D02C347972','D78E9D1F-D616-4B21-9B4D-5D97CD825101')
}
if (-not $ResumeAfterRepair -and (Test-Path $registration)) { throw 'A development Setup installation is already registered; preserve it and test in another Windows account.' }
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Emacsvox Windows.lnk'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Emacsvox Windows'
if ($IsolatedIdentity) {
    $desktop = $desktop.Replace('Emacsvox Windows','Emacsvox UI Fixture')
    $menu = $menu.Replace('Emacsvox Windows','Emacsvox UI Fixture')
}
if (-not $ResumeAfterRepair -and ((Test-Path $desktop) -or (Test-Path $menu))) { throw 'Existing development shortcuts would be changed; use another test account.' }
$work = if ($ResumeAfterRepair) { [IO.Path]::GetFullPath($ResumeAfterRepair).TrimEnd('\') }
        else { Join-Path $env:TEMP ('evox setup test ' + [guid]::NewGuid().ToString('N').Substring(0,12)) }
$installation = Join-Path $work 'installed desktop'
if ($ResumeAfterRepair) {
    if ((Split-Path $work -Parent) -ne $env:TEMP.TrimEnd('\') -or
        (Split-Path $work -Leaf) -notmatch '^evox setup test [a-f0-9]{12}$' -or
        (Get-ItemProperty -LiteralPath $registration).InstallLocation.TrimEnd('\') -ne $installation) {
        throw 'Resume requires the registered isolated test fixture, not a personal installation.'
    }
    foreach ($name in @('first-install.log','repair.log')) {
        if ([IO.File]::ReadAllText((Join-Path $work $name)) -notmatch 'Installation process succeeded') {
            throw "The retained fixture has not completed $name"
        }
    }
} else { New-Item -ItemType Directory $work | Out-Null }
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
    if (-not $ResumeAfterRepair) { Run-Setup $Setup 'first-install.log' }
    if (-not (Test-Path $registration) -or -not (Test-Path $desktop) -or -not (Test-Path $menu)) {
        throw 'Setup did not register the per-user installation and shortcuts'
    }
    $currentPath = Join-Path $installation 'current.json'
    $first = [IO.File]::ReadAllText($currentPath) | ConvertFrom-Json
    $application = Join-Path $installation "Applications\$($first.Build)"
    $config = [IO.File]::ReadAllText((Join-Path $application 'native-install.json')) | ConvertFrom-Json
    $profile = Join-Path $config.Profile 'preserved-profile.txt'
    $voices = Join-Path $installation 'voices'
    $voice = Join-Path $voices 'preserved-voice.txt'
    if ($ResumeAfterRepair) {
        if ([IO.File]::ReadAllText($profile) -ne 'profile survives setup and uninstall' -or
            [IO.File]::ReadAllText($voice) -ne 'user voice stays') { throw 'The retained fixture has changed user data' }
    } else {
        [IO.File]::WriteAllText($profile, 'profile survives setup and uninstall')
        New-Item -ItemType Directory $voices | Out-Null
        [IO.File]::WriteAllText($voice, 'user voice stays')
    }
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
    if (-not $ResumeAfterRepair) {
        $start.FileName = $config.Emacs
        $start.Arguments = (@('-Q','--batch','--eval','(sleep-for 180)') | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
        $running = [Diagnostics.Process]::Start($start)
        Run-Setup $Setup 'running-refused.log' -ExpectFailure
        if ([IO.File]::ReadAllText((Join-Path $work 'running-refused.log')) -notmatch 'Close the Emacsvox application') {
            throw 'Setup failed without reporting the running application'
        }
        $refused = $false
        try {
            Invoke-EmacsvoxNative (Join-Path $installation 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',
                ('/LOG=' + (Join-Path $work 'uninstall-refused.log'))) -TimeoutSeconds 120 | Out-Null
        }
        catch { $refused = $true }
        if (-not $refused -or -not (Test-Path $registration) -or
            [IO.File]::ReadAllText((Join-Path $work 'uninstall-refused.log')) -notmatch 'Close the Emacsvox application') {
            throw 'Uninstall did not safely refuse a running installation'
        }
        if ($running.HasExited) { throw 'Setup closed the running Emacs' }
        $running.Kill(); $running.WaitForExit(); $running.Dispose(); $running = $null
        $missing = Join-Path $application 'lisp\emacsvox-wizards.el'
        Remove-Item -LiteralPath $missing
        Run-Setup $Setup 'repair.log'
        if (-not (Test-Path $missing) -or [IO.File]::ReadAllText($profile) -ne 'profile survives setup and uninstall') {
            throw 'Repair failed or changed the profile'
        }
    }
    if ($FailedUpgrade) {
        $previous = [IO.File]::ReadAllText($currentPath)
        $previousName = (Get-ItemProperty -LiteralPath $registration).DisplayName
        $shared = @('Launcher\Start.ps1','Setup\emacsvox-windows-setup-helper.ps1','Setup\emacsvox-windows-common.ps1')
        $previousHashes = @{}
        foreach ($name in $shared) { $previousHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $installation $name)).Hash }
        Run-Setup $FailedUpgrade 'failed-upgrade.log' -ExpectFailure
        $failureLog = [IO.File]::ReadAllText((Join-Path $work 'failed-upgrade.log'))
        if ($failureLog -notmatch 'Intentional configuration failure for rollback acceptance' -or
            $failureLog -notmatch 'Rolling back changes') {
            throw 'The failure fixture did not reach configuration failure and rollback'
        }
        if ([IO.File]::ReadAllText($currentPath) -ne $previous) { throw 'Failed upgrade changed the working selection' }
        if ((Get-ItemProperty -LiteralPath $registration).DisplayName -ne $previousName) { throw 'Failed upgrade changed registration' }
        foreach ($name in $shared) {
            if ((Get-FileHash -LiteralPath (Join-Path $installation $name)).Hash -ne $previousHashes[$name]) {
                throw "Failed configuration changed the working launcher or helpers: $name"
            }
        }
        Check-Launcher
    }
    if ($Upgrade) {
        # A Windows file handle can prevent atomic activation after files have
        # installed successfully. Report failure, preserve the old selection,
        # and allow the same installer to repair/activate after releasing it.
        $previous = [IO.File]::ReadAllText($currentPath)
        $locked = [IO.File]::Open($currentPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try { Run-Setup $Upgrade 'activation-refused.log' -ExpectFailure }
        finally { $locked.Dispose() }
        if ([IO.File]::ReadAllText((Join-Path $work 'activation-refused.log')) -notmatch 'Installation process succeeded') {
            throw 'The activation test failed before reaching activation'
        }
        if ([IO.File]::ReadAllText($currentPath) -ne $previous) { throw 'Failed activation changed the working selection' }
        Check-Launcher
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
    if ($Upgrade) { Write-Host 'PASS: failed activation preserved the selection; repair activated a different build with the same profile.' }
    else { Write-Host 'Upgrade acceptance was skipped; pass a second build with -Upgrade.' }
    if ($FailedUpgrade) { Write-Host 'PASS: failed upgrade preserved the previous working selection and launcher.' }
    if (-not $AudioCheck) { Write-Host 'Graphical/audio acceptance was skipped.' }
}
finally {
    if ($running) { if (-not $running.HasExited) { $running.Kill(); $running.WaitForExit() }; $running.Dispose() }
    $env:PATH = $oldPath
    if ($null -eq $oldEmacs) { Remove-Item Env:EMACS -ErrorAction SilentlyContinue } else { $env:EMACS = $oldEmacs }
    Write-Host "Retained setup acceptance logs: $work"
    if (-not $passed) { Write-Host 'The isolated test installation was retained for diagnosis.' }
    if ($LogDirectory) {
        Get-ChildItem -LiteralPath $work -Filter '*.log' -File | Copy-Item -Destination $LogDirectory
        $installLogs = Join-Path $installation 'logs'
        if (Test-Path -LiteralPath $installLogs) {
            Copy-Item -LiteralPath $installLogs -Destination (Join-Path $LogDirectory 'installation') -Recurse
        }
        Write-EmacsvoxJson (Join-Path $LogDirectory 'result.json') @{
            Schema=1; Passed=$passed; AudioCheck=[bool]$AudioCheck;
            UpgradeRequested=[bool]$Upgrade; RollbackRequested=[bool]$FailedUpgrade
        }
    }
}
