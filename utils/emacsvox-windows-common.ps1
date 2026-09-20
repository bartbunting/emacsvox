# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-EmacsvoxPins([string]$Path) {
    $pins = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*(#.*)?$') { continue }
        if ($line -notmatch '^([A-Z][A-Z0-9_]*)=([A-Za-z0-9_./:+-]+)$') {
            throw "Invalid installation manifest line in $Path"
        }
        if ($pins.ContainsKey($Matches[1])) { throw "Duplicate installation pin: $($Matches[1])" }
        $pins[$Matches[1]] = $Matches[2]
    }
    return $pins
}

function Assert-NativeWindows(
    [string]$Platform = [Environment]::OSVersion.Platform.ToString(),
    [string]$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
) {
    if ($Platform -ne 'Win32NT') { throw 'This installer requires native Windows.' }
    if ($Architecture -ne 'X64') { throw "This installer is supported only on Windows x64; detected $Architecture." }
}

function Assert-WindowsLocalPath([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path -match '[\r\n]') {
        throw "Use an absolute local Windows drive path, not a WSL or network checkout: $Path"
    }
}

function ConvertTo-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including embedded quotes and trailing backslashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function ConvertTo-EmacsvoxLispString([string]$Value) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
    return '(decode-coding-string (base64-decode-string "' + $encoded + '") (quote utf-8))'
}

function Get-EmacsvoxLoadExpression([string]$Path) {
    return '(load ' + (ConvertTo-EmacsvoxLispString $Path) + ' nil t)'
}

function Invoke-EmacsvoxNative {
    param([string]$Program, [string[]]$Arguments, [hashtable]$Environment = @{},
          [string]$Log, [int]$TimeoutSeconds = 120)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Program
    $start.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { $start.EnvironmentVariables.Remove($key) }
        else { $start.EnvironmentVariables[$key] = [string]$Environment[$key] }
    }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $Program" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Timed out running $Program; inspect $Log"
        }
        $output = $stdout.Result + $stderr.Result
        if ($Log) { [IO.File]::WriteAllText($Log, $output) }
        if ($process.ExitCode -ne 0) {
            throw "$Program failed (exit $($process.ExitCode)). $output Log: $Log"
        }
        return $stdout.Result.Trim()
    }
    finally { $process.Dispose() }
}

function Get-EmacsvoxNativeEmacs([string]$Program) {
    $command = Get-Command $Program -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw "Selected Emacs does not exist: $Program" }
    $path = $command.Source
    $output = Invoke-EmacsvoxNative $path @('-Q', '--batch', '--eval',
        '(progn (unless (and (eq system-type (quote windows-nt)) (version<= "30.2" emacs-version)) (error "Native Windows Emacs 30.2+ required")) (princ emacs-version))')
    if ($output -notmatch '^\d+\.\d+(?:[.0-9A-Za-z+-]*)$') { throw "Unexpected Emacs version: $output" }
    return @{ Program = $path; Version = $output }
}

function Get-EmacsvoxArchive([string]$Url, [string]$Path, [string]$Hash, [switch]$Offline) {
    if ($Hash -notmatch '^[a-f0-9]{64}$' -or $Url -notmatch '^https://') { throw 'Invalid archive pin.' }
    if (Test-Path -LiteralPath $Path) {
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Hash) {
            throw "Checksum mismatch in cached archive: $Path. Remove that file and retry."
        }
        return $Path
    }
    if ($Offline) { throw "Offline archive missing: $Path. Prepare the complete offline bundle first." }
    New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
    $temporary = "$Path.part-$([guid]::NewGuid().ToString('N'))"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporary -TimeoutSec 600
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ine $Hash) { throw "Checksum mismatch: $Url" }
        Move-Item -LiteralPath $temporary -Destination $Path
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    return $Path
}

function Install-EmacsvoxPrebuiltEmacs {
    param([string]$Archive, [string]$Destination, [string]$Version, [string]$ArchiveHash)
    Assert-WindowsLocalPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Emacs destination already exists: $Destination" }
    $stage = Join-Path (Split-Path $Destination -Parent) ('.stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force (Split-Path $Destination -Parent) | Out-Null
    try {
        Expand-EmacsvoxZip $Archive $stage
        foreach ($file in @('bin\emacs.exe', 'bin\runemacs.exe', "share\emacs\$Version\etc\COPYING")) {
            if (-not (Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) {
                throw "Prebuilt Emacs archive lacks $file"
            }
        }
        # Move before executing: Windows can retain an executable lock briefly
        # after a probe exits. The receipt is written only after validation.
        [IO.Directory]::Move($stage, $Destination)
        try {
            $selected = Get-EmacsvoxNativeEmacs (Join-Path $Destination 'bin\emacs.exe')
            if ($selected.Version -ne $Version) { throw "Prebuilt Emacs reports $($selected.Version), expected $Version" }
            Invoke-EmacsvoxNative $selected.Program @('-Q', '--batch', '--eval',
                '(unless (and (gnutls-available-p) (sqlite-available-p) (treesit-available-p) (fboundp (quote libxml-parse-xml-region))) (error "Required native Emacs features missing"))') | Out-Null
            Write-EmacsvoxJson (Join-Path $Destination 'emacsvox-build.json') @{
                Schema = 1; Kind = 'verified-prebuilt'; Emacs = $Version; ArchiveSHA256 = $ArchiveHash
            }
        }
        catch {
            Remove-Item -Recurse -Force -LiteralPath $Destination
            throw
        }
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force -LiteralPath $stage } }
    return Get-EmacsvoxNativeEmacs (Join-Path $Destination 'bin\emacs.exe')
}

function Expand-EmacsvoxZip([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '(^[\\/]|:|(^|[\\/])\.\.([\\/]|$))') {
                throw "Unsafe archive entry: $($entry.FullName)"
            }
            if ([IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName)).Length -ge 248) {
                throw 'Archive paths are too long for Windows PowerShell 5.1. Choose a shorter extraction or installation directory.'
            }
        }
    }
    finally { $zip.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Destination)
}

function Write-EmacsvoxJson([string]$Path, $Value) {
    $temporary = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
