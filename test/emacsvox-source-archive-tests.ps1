# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Archive,
    [Parameter(Mandatory=$true)][string]$Emacs
)
$ErrorActionPreference = 'Stop'
$work = Join-Path $env:TEMP ('emacsvox archive tests ' + [guid]::NewGuid().ToString('N'))
$oldEmacs = $env:EMACS
Remove-Item Env:EMACS -ErrorAction SilentlyContinue
New-Item -ItemType Directory $work | Out-Null
try {
    & tar.exe -xf $Archive -C $work
    if ($LASTEXITCODE -ne 0) { throw 'Source archive extraction failed' }
    $roots = @(Get-ChildItem $work -Directory)
    if ($roots.Count -ne 1) { throw 'Expected one archive root' }
    $root = $roots[0].FullName
    . (Join-Path $root 'utils\emacsvox-windows-common.ps1')
    $native = Get-EmacsvoxNativeEmacs $Emacs
    $install = Join-Path $work 'installation'
    $cache = Join-Path $work 'downloads'
    & (Join-Path $root 'bin\emacsvox-install.ps1') -Emacs $native.Program -Check `
        -InstallRoot $install -CacheDirectory $cache
    if ((Test-Path $install) -or (Test-Path $cache) -or (Test-Path (Join-Path $root 'native-install.json'))) {
        throw 'Archive installer doctor changed installation state'
    }
    $privateHome = Join-Path $work 'home'
    New-Item -ItemType Directory $privateHome | Out-Null
    $environment = @{
        HOME = $privateHome
        EMACSVOX_NATIVE_ROOT = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root))
        EMACSVOX_NATIVE_BYTECODE = 'build'
    }
    $arguments = @('-Q', '--batch', '--eval',
        (Get-EmacsvoxLoadExpression (Join-Path $root 'utils\emacsvox-native-bytecode.el')),
        '--funcall', 'emacsvox-native-bytecode-main')
    Invoke-EmacsvoxNative $native.Program $arguments $environment -TimeoutSeconds 1200
    $environment.EMACSVOX_NATIVE_BYTECODE = 'check'
    Invoke-EmacsvoxNative $native.Program $arguments $environment
    Write-Host 'PASS: extracted archive native Windows doctor, full compilation and fresh byte-code check.'
}
finally {
    if ($null -eq $oldEmacs) { Remove-Item Env:EMACS -ErrorAction SilentlyContinue }
    else { $env:EMACS = $oldEmacs }
    Remove-Item -LiteralPath $work -Recurse -Force
}
