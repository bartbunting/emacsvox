# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Emacs)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'utils\emacsvox-windows-common.ps1')
$native = Get-EmacsvoxNativeEmacs $Emacs
$testRoot = Join-Path $env:TEMP ('emacsvox windows tests ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testRoot | Out-Null
$oldEmacs = $env:EMACS
Remove-Item Env:EMACS -ErrorAction SilentlyContinue
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Expected rejection: $Message" }
}
try {
    foreach ($directory in @('bin', 'utils', 'etc')) {
        $target = Join-Path $testRoot $directory
        New-Item -ItemType Directory $target | Out-Null
        Get-ChildItem (Join-Path $repo $directory) -File |
            Where-Object { $_.Extension -in @('.ps1', '.conf') } | Copy-Item -Destination $target
    }
    $installer = Join-Path $testRoot 'bin\emacsvox-install.ps1'
    $install = Join-Path $testRoot 'installation'
    $cache = Join-Path $testRoot 'downloads'
    & $installer -Emacs $native.Program -Check -InstallRoot $install -CacheDirectory $cache
    if ((Test-Path $install) -or (Test-Path $cache) -or (Test-Path (Join-Path $testRoot 'native-install.json'))) {
        throw 'Doctor mutated the filesystem'
    }
    $settings = Join-Path $testRoot 'native-install.json'
    Write-EmacsvoxJson $settings @{ Schema=1; Role='Desktop'; Emacs=$native.Program;
        Profile=(Join-Path $install 'profile'); ToolchainRoot='C:\EmacsvoxTestTools'; CacheDirectory=$cache }
    $savedHash = (Get-FileHash $settings).Hash
    & $installer -Check
    if ((Test-Path $install) -or (Test-Path $cache) -or (Get-FileHash $settings).Hash -ne $savedHash) {
        throw 'Saved-selection doctor changed installation state'
    }
    Remove-Item $settings
    # A missing Emacs offers choices before any download or toolchain probing.
    $oldPath = $env:PATH
    try {
        $env:PATH = "$env:SystemRoot\System32"
        $choice = & $installer -Check -InstallRoot $install -CacheDirectory $cache `
            -ToolchainRoot (Join-Path $testRoot 'unused tools') 6>&1 | Out-String
        if ($choice -notmatch 'prebuilt Windows Emacs 30.2' -or $choice -notmatch '-BuildEmacs') {
            throw 'Missing Emacs did not offer prebuilt and source choices'
        }
        Assert-Rejected { & $installer -InstallRoot $install -CacheDirectory $cache } 'Select a prebuilt Emacs'
        Assert-Rejected { & $installer -BuildEmacs -Check -InstallRoot $install `
            -ToolchainRoot (Join-Path $testRoot 'unused tools') } 'path without spaces'
        if ((Test-Path $install) -or (Test-Path $cache)) { throw 'Choice prompt mutated the filesystem' }
    }
    finally { $env:PATH = $oldPath }
    Assert-Rejected { & $installer -Emacs $native.Program -BuildEmacs -Check } 'cannot replace an explicit'
    Assert-Rejected { & $installer -Emacs '' -Check } 'cannot be empty'
    Assert-Rejected { & $installer -Emacs 'Z:\missing\emacs.exe' -Check } 'does not exist'
    Assert-Rejected { & $installer -Role 'SpeechHost' -Check } '*'
    $local = Join-Path $testRoot 'local.mk'
    [IO.File]::WriteAllText($local, "EXTRA = preserved`r`nEMACS = Z:/conflicting/emacs.exe`r`n")
    $before = (Get-FileHash $local).Hash
    Assert-Rejected { & $installer -Emacs $native.Program -Check } 'Align the explicit'
    if ((Get-FileHash $local).Hash -ne $before) { throw 'Explicit selection was overwritten' }
    Remove-Item $local
    $pins = Read-EmacsvoxPins (Join-Path $repo 'etc\wsl-install.conf')
    $partial = Join-Path $install "Omnivox\$($pins.EMACSVOX_WSL_OMNIVOX_VERSION)-windows-x64"
    New-Item -ItemType Directory -Force $partial | Out-Null
    Assert-Rejected { & $installer -Emacs $native.Program -Check -InstallRoot $install } 'Incomplete Omnivox'
    Remove-Item $install -Recurse -Force

    $badArchive = Join-Path $testRoot 'bad.zip'
    [IO.File]::WriteAllText($badArchive, 'not a release archive')
    Assert-Rejected { Get-EmacsvoxArchive 'https://example.invalid/never-download' $badArchive ('0' * 64) } 'Checksum mismatch'
    $manifest = Join-Path $testRoot 'bad.conf'
    [IO.File]::WriteAllText($manifest, 'PIN=$(not-executed)')
    Assert-Rejected { Read-EmacsvoxPins $manifest } 'Invalid installation manifest'
    Assert-Rejected { Assert-WindowsLocalPath '\\wsl.localhost\Ubuntu\home\test' } 'absolute local Windows'
    Assert-Rejected { Assert-WindowsLocalPath 'relative\checkout' } 'absolute local Windows'
    Assert-Rejected { Assert-NativeWindows 'Unix' 'X64' } 'requires native Windows'
    Assert-Rejected { Assert-NativeWindows 'Win32NT' 'Arm64' } 'only on Windows x64'
    $zip = Join-Path $testRoot 'unsafe.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
    $archive.CreateEntry('../escaped.txt') | Out-Null
    $archive.Dispose()
    Assert-Rejected { Expand-EmacsvoxZip $zip (Join-Path $testRoot 'extracted') } 'Unsafe archive entry'
    if (Test-Path (Join-Path $testRoot 'escaped.txt')) { throw 'Archive escaped staging' }

    # Prove exact Windows argument handling with real native Emacs, including
    # quotes, shell metacharacters, Unicode and a trailing backslash.
    $value = 'space " quote $() & trailing\'
    $quoted = Invoke-EmacsvoxNative $native.Program @('-Q','--batch','--eval',
        '(princ (base64-encode-string (encode-coding-string (pop command-line-args-left) (quote utf-8)) t))', $value)
    $quoted = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($quoted))
    if ($quoted -cne $value) { throw "Native argument round-trip failed: $quoted" }
    $value += [char]0xE9
    $expression = '(princ (base64-encode-string (encode-coding-string ' + (ConvertTo-EmacsvoxLispString $value) + ' (quote utf-8)) t))'
    $encoded = Invoke-EmacsvoxNative $native.Program @('-Q','--batch','--eval', $expression)
    if ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) -cne $value) {
        throw 'Unicode Lisp data transport failed'
    }
    $json = Join-Path $testRoot 'settings.json'
    Write-EmacsvoxJson $json @{ Value = 'first' }
    Write-EmacsvoxJson $json @{ Value = $value }
    if (([IO.File]::ReadAllText($json) | ConvertFrom-Json).Value -cne $value) { throw 'Configuration data changed' }
    Write-Host 'PASS: native doctor, explicit selection, incomplete install, checksum, archive layout, argument quoting and atomic configuration.'
}
finally {
    if ($null -eq $oldEmacs) { Remove-Item Env:EMACS -ErrorAction SilentlyContinue }
    else { $env:EMACS = $oldEmacs }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
