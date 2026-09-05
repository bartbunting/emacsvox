# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([switch]$Diagnose, [switch]$Check)
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
if ($Diagnose -and $Check) { throw 'Choose either -Diagnose or -Check.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
Assert-WindowsLocalPath $root
$configFile = Join-Path $root 'native-install.json'
if (-not (Test-Path $configFile)) { throw 'Run bin\emacsvox-install.ps1 first.' }
$config = [IO.File]::ReadAllText($configFile) | ConvertFrom-Json
if ($config.Schema -ne 1 -or $config.Role -ne 'Desktop') { throw 'Unsupported native installation configuration.' }
$selected = Get-EmacsvoxNativeEmacs $config.Emacs
if ($env:EMACS -and $env:EMACS -ne $selected.Program) { throw 'EMACS conflicts with native-install.json; rerun the installer with the intended selection.' }
if (-not (Test-Path -LiteralPath $config.Omnivox)) { throw 'Installed Omnivox is missing; rerun the installer.' }
$environment = @{ EMACSVOX_DIR = $root; EMACSVOX_NATIVE_ROOT = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root)); EMACSVOX_NATIVE_BYTECODE = 'check'; TTS_PROGRAM = $config.Omnivox;
    ESPEAK_NG_DATA = (Join-Path (Split-Path $config.Omnivox -Parent) 'espeak-ng-data');
    OMNIVOX_ENGINE = 'winrt'; EMACSVOX_PLAY = $null; OMNIVOX_AUDIO_OUTPUT = $null;
    EMACSVOX_NATIVE_RESULT = $null }
if ($env:OMNIVOX_ENGINE) { $environment.OMNIVOX_ENGINE = $env:OMNIVOX_ENGINE }
Invoke-EmacsvoxNative $selected.Program @('-Q', '--batch', '--eval',
    (Get-EmacsvoxLoadExpression (Join-Path $root 'utils\emacsvox-native-bytecode.el')), '--funcall', 'emacsvox-native-bytecode-main') $environment | Out-Null
Write-Host "Native Windows Emacs $($selected.Version): $($selected.Program)"
Write-Host "Omnivox: $($config.Omnivox); engine: $($environment.OMNIVOX_ENGINE)"
Write-Host "Isolated profile: $($config.Profile)"
if ($Diagnose) { Write-Host 'Speech was not tested.'; return }
$arguments = @('-Q', '--no-splash', '--name', 'Emacsvox Native Windows',
    '--eval', (Get-EmacsvoxLoadExpression (Join-Path $root 'utils\emacsvox-windows-startup.el')))
$data = @{ Root = $root; Profile = $config.Profile; Omnivox = $config.Omnivox; Result = $null }
if ($Check) {
    New-Item -ItemType Directory -Force $config.Logs | Out-Null
    $result = Join-Path $config.Logs ("native-startup-$([guid]::NewGuid().ToString('N')).txt")
    $data.Result = $result
    $environment.EMACSVOX_NATIVE_SETTINGS = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json)))
    Invoke-EmacsvoxNative $selected.Program $arguments $environment (Join-Path $config.Logs 'native-startup.log') 150 | Out-Null
    if (-not (Test-Path $result) -or (Get-Content -Raw $result) -notmatch '^PASS:') { throw "Startup check did not pass; inspect $result" }
    Write-Host (Get-Content -Raw $result)
    Write-Host 'Confirm that you heard both announcements.'
}
else {
    $environment.EMACSVOX_NATIVE_SETTINGS = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json)))
    # The child keeps its own environment after PowerShell exits.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $selected.Program
    $start.Arguments = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    foreach ($key in $environment.Keys) {
        if ($null -eq $environment[$key]) { $start.EnvironmentVariables.Remove($key) }
        else { $start.EnvironmentVariables[$key] = [string]$environment[$key] }
    }
    $process = [Diagnostics.Process]::Start($start)
    $process.Dispose()
}
