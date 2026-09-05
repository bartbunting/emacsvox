# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [ValidateSet('Desktop')][string]$Role = 'Desktop',
    [switch]$Check,
    [string]$Emacs,
    [switch]$BuildEmacs,
    [string]$InstallRoot = "$env:LOCALAPPDATA\Emacsvox\Native",
    [string]$ToolchainRoot = "$env:LOCALAPPDATA\Emacsvox\Toolchains\msys2-20260611",
    [string]$CacheDirectory = "$env:LOCALAPPDATA\Emacsvox\Downloads",
    [ValidateRange(1,64)][int]$Jobs = [Math]::Min(8, [Environment]::ProcessorCount),
    [switch]$NoAudioCheck
)
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
Assert-NativeWindows
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
foreach ($path in @($root, $InstallRoot, $ToolchainRoot, $CacheDirectory)) { Assert-WindowsLocalPath $path }
$pins = Read-EmacsvoxPins (Join-Path $root 'etc\wsl-install.conf')
$windowsPins = Read-EmacsvoxPins (Join-Path $root 'etc\windows-install.conf')
if ($pins.EMACSVOX_WSL_INSTALL_SCHEMA -ne '1' -or $windowsPins.EMACSVOX_WINDOWS_INSTALL_SCHEMA -ne '1') {
    throw 'Unsupported installation manifest schema.'
}
$configFile = Join-Path $root 'native-install.json'
$saved = if (Test-Path $configFile) { [IO.File]::ReadAllText($configFile) | ConvertFrom-Json } else { $null }
if ($saved -and ($saved.Schema -ne 1 -or $saved.Role -ne 'Desktop')) {
    throw 'Unsupported saved native installation configuration.'
}
if ($saved) {
    if (-not $PSBoundParameters.ContainsKey('InstallRoot')) {
        $InstallRoot = Split-Path $saved.Profile -Parent
    }
    if (-not $PSBoundParameters.ContainsKey('ToolchainRoot') -and $saved.PSObject.Properties['ToolchainRoot']) {
        $ToolchainRoot = $saved.ToolchainRoot
    }
    if (-not $PSBoundParameters.ContainsKey('CacheDirectory') -and $saved.PSObject.Properties['CacheDirectory']) {
        $CacheDirectory = $saved.CacheDirectory
    }
    foreach ($path in @($InstallRoot, $ToolchainRoot, $CacheDirectory)) { Assert-WindowsLocalPath $path }
}
$localMk = Join-Path $root 'local.mk'
$localEmacs = $null
if (Test-Path $localMk) {
    foreach ($line in [IO.File]::ReadAllLines($localMk)) {
        if ($line -match '^\s*EMACS\s*=\s*(.*?)\s*$') { $localEmacs = $Matches[1] }
    }
}
$explicit = @()
if ($PSBoundParameters.ContainsKey('Emacs')) {
    if (-not $Emacs) { throw '-Emacs cannot be empty.' }
    $explicit += $Emacs
}
if ($env:EMACS) { $explicit += $env:EMACS }
if ($null -ne $localEmacs) {
    if (-not $localEmacs) { throw 'local.mk selects an empty EMACS.' }
    $explicit += $localEmacs
}
if (@($explicit | Select-Object -Unique).Count -gt 1) { throw 'Align the explicit -Emacs, EMACS and local.mk selections.' }
if ($BuildEmacs -and $explicit.Count) { throw '-BuildEmacs cannot replace an explicit Emacs selection; unset or align it first.' }
$prefix = Join-Path $InstallRoot "Emacs\$($pins.EMACSVOX_WSL_EMACS_VERSION)-ucrt64"
$selected = $null
if ($explicit.Count) { $selected = Get-EmacsvoxNativeEmacs $explicit[0] }
elseif (-not $BuildEmacs -and $saved) { $selected = Get-EmacsvoxNativeEmacs $saved.Emacs }
elseif (Test-Path $prefix) {
    if (-not (Test-Path (Join-Path $prefix 'emacsvox-build.json'))) {
        throw "Incomplete managed Emacs installation: $prefix"
    }
    $selected = Get-EmacsvoxNativeEmacs (Join-Path $prefix 'bin\emacs.exe')
    if ($selected.Version -ne $pins.EMACSVOX_WSL_EMACS_VERSION) { throw "Unexpected Emacs in $prefix" }
}
elseif (-not $BuildEmacs) {
    $candidate = Get-Command emacs.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) {
        try { $selected = Get-EmacsvoxNativeEmacs $candidate.Source }
        catch { Write-Host 'PATH has no usable native Emacs 31+; the pinned build will be used.' }
    }
}
$omnivoxRoot = Join-Path $InstallRoot "Omnivox\$($pins.EMACSVOX_WSL_OMNIVOX_VERSION)-windows-x64"
$omnivox = Join-Path $omnivoxRoot 'omnivox.exe'
$logs = Join-Path $InstallRoot 'logs'
$profile = Join-Path $InstallRoot 'profile'
$msys = Join-Path $ToolchainRoot 'msys64'
$bash = Join-Path $msys 'usr\bin\bash.exe'
if (-not $selected) {
    if ($ToolchainRoot -match '\s') { throw 'MSYS2 build tools need a path without spaces; select -ToolchainRoot accordingly.' }
    if ((Test-Path $ToolchainRoot) -and -not (Test-Path (Join-Path $ToolchainRoot 'emacsvox-toolchain.json'))) {
        throw "Unmanaged or incomplete toolchain: $ToolchainRoot. Choose a new -ToolchainRoot."
    }
    if ((Test-Path (Join-Path $msys 'emacsvox-build')) -or (Test-Path (Join-Path $msys 'emacsvox-output'))) {
        throw 'Previous build files remain in the toolchain. Inspect them and choose a new -ToolchainRoot for a fresh build.'
    }
}
if (Test-Path $omnivoxRoot) {
    foreach ($file in @('omnivox.exe', 'espeak-ng-data\phontab', 'third-party-licenses\THIRD-PARTY-NOTICES.md')) {
        if (-not (Test-Path (Join-Path $omnivoxRoot $file))) { throw "Incomplete Omnivox installation: $omnivoxRoot" }
    }
    $version = Invoke-EmacsvoxNative $omnivox @('--version')
    if ($version -ne "omnivox $($pins.EMACSVOX_WSL_OMNIVOX_VERSION)") { throw "Unexpected Omnivox version: $version" }
}
Write-Host "Native Windows x64 preview; role: $Role"
if ($selected) { Write-Host "Emacs: $($selected.Program) ($($selected.Version))" }
else { Write-Host "Emacs: build GNU $($pins.EMACSVOX_WSL_EMACS_VERSION) using private MSYS2 UCRT64 at $ToolchainRoot" }
Write-Host "Omnivox: pinned $($pins.EMACSVOX_WSL_OMNIVOX_VERSION) at $omnivoxRoot"
Write-Host "Checkout: $root"
Write-Host "Configuration: $configFile"
Write-Host "Profile: $profile"
if ($Check) { Write-Host 'No files changed. Speech and downloads were not tested.'; return }
New-Item -ItemType Directory -Force $InstallRoot, $logs, $CacheDirectory, $profile | Out-Null

if (-not $selected) {
    if (-not (Test-Path $ToolchainRoot)) {
        $bootstrap = Get-EmacsvoxArchive $windowsPins.EMACSVOX_WINDOWS_MSYS2_URL `
            (Join-Path $CacheDirectory $windowsPins.EMACSVOX_WINDOWS_MSYS2_ARCHIVE) $windowsPins.EMACSVOX_WINDOWS_MSYS2_SHA256
        $stage = "$ToolchainRoot.stage-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force (Split-Path $ToolchainRoot -Parent) | Out-Null
        try {
            Write-Host 'Extracting verified private MSYS2 toolchain.'
            Invoke-EmacsvoxNative $bootstrap @('-y', "-o$stage") -Log (Join-Path $logs 'msys2-extract.log') | Out-Null
            if (-not (Test-Path (Join-Path $stage 'msys64\usr\bin\bash.exe'))) { throw 'Unexpected MSYS2 bootstrap layout.' }
            Write-EmacsvoxJson (Join-Path $stage 'emacsvox-toolchain.json') @{ BootstrapSHA256 = $windowsPins.EMACSVOX_WINDOWS_MSYS2_SHA256 }
            Move-Item -LiteralPath $stage -Destination $ToolchainRoot
        }
        finally { if (Test-Path $stage) { Remove-Item -Recurse -Force -LiteralPath $stage } }
    }
    $marker = [IO.File]::ReadAllText((Join-Path $ToolchainRoot 'emacsvox-toolchain.json')) | ConvertFrom-Json
    if ($marker.BootstrapSHA256 -ne $windowsPins.EMACSVOX_WINDOWS_MSYS2_SHA256 -or -not (Test-Path $bash)) {
        throw 'Toolchain identity mismatch or incomplete installation.'
    }
    $buildEnvironment = @{ MSYSTEM = 'UCRT64'; CHERE_INVOKING = '1'; MSYS2_PATH_TYPE = 'minimal';
        EMACSVOX_NATIVE_VERSION = $pins.EMACSVOX_WSL_EMACS_VERSION; EMACSVOX_NATIVE_JOBS = $Jobs }
    Write-Host 'Updating the private MSYS2 installation (signed rolling packages).'
    Invoke-EmacsvoxNative $bash @('--login', '-c', 'pacman --noconfirm -Syuu') $buildEnvironment (Join-Path $logs 'msys2-update-1.log') 1800 | Out-Null
    Invoke-EmacsvoxNative $bash @('--login', '-c', 'pacman --noconfirm -Syuu') $buildEnvironment (Join-Path $logs 'msys2-update-2.log') 1800 | Out-Null
    $packages = 'base-devel mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-xpm-nox mingw-w64-ucrt-x86_64-giflib mingw-w64-ucrt-x86_64-libpng mingw-w64-ucrt-x86_64-libtiff mingw-w64-ucrt-x86_64-libjpeg-turbo mingw-w64-ucrt-x86_64-librsvg mingw-w64-ucrt-x86_64-lcms2 mingw-w64-ucrt-x86_64-gnutls mingw-w64-ucrt-x86_64-libxml2 mingw-w64-ucrt-x86_64-libtree-sitter mingw-w64-ucrt-x86_64-sqlite3'
    Write-Host 'Installing private compiler and Emacs build dependencies.'
    Invoke-EmacsvoxNative $bash @('--login', '-c', "pacman --noconfirm -S --needed $packages") $buildEnvironment (Join-Path $logs 'msys2-packages.log') 1800 | Out-Null
    $archive = Get-EmacsvoxArchive $pins.EMACSVOX_WSL_EMACS_URL `
        (Join-Path $CacheDirectory $pins.EMACSVOX_WSL_EMACS_ARCHIVE) $pins.EMACSVOX_WSL_EMACS_SHA256
    $work = Join-Path $msys 'emacsvox-build'
    if (Test-Path $work) { throw "Previous build files remain at $work. Inspect them and select a new -ToolchainRoot for a fresh build." }
    if (Test-Path (Join-Path $msys 'emacsvox-output')) { throw 'An unactivated Emacs build remains in the private toolchain.' }
    Copy-Item -LiteralPath $archive -Destination (Join-Path $msys 'emacsvox-source.tar.xz')
    # Preserve LF for bash even in a checkout made with Git's autocrlf enabled.
    $buildScript = [IO.File]::ReadAllText((Join-Path $root 'utils\emacsvox-windows-build.sh')).Replace("`r`n", "`n")
    [IO.File]::WriteAllText((Join-Path $msys 'emacsvox-build.sh'), $buildScript, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Building native Emacs. Detailed logs: $work\logs"
    Invoke-EmacsvoxNative $bash @('--login', '/emacsvox-build.sh') $buildEnvironment (Join-Path $logs 'emacs-build.log') 7200 | Out-Null
    New-Item -ItemType Directory -Force (Split-Path $prefix -Parent) | Out-Null
    Move-Item -LiteralPath (Join-Path $msys 'emacsvox-output') -Destination $prefix
    $selected = Get-EmacsvoxNativeEmacs (Join-Path $prefix 'bin\emacs.exe')
    Invoke-EmacsvoxNative $selected.Program @('-Q', '--batch', '--eval',
        '(unless (and (gnutls-available-p) (sqlite-available-p) (treesit-available-p) (fboundp (quote libxml-parse-xml-region))) (error "Required native Emacs features missing"))') | Out-Null
    Copy-Item -LiteralPath (Join-Path $work 'logs') -Destination (Join-Path $prefix 'build-logs') -Recurse
    Write-EmacsvoxJson (Join-Path $prefix 'emacsvox-build.json') @{ Emacs = $selected.Version; SourceSHA256 = $pins.EMACSVOX_WSL_EMACS_SHA256; BootstrapSHA256 = $windowsPins.EMACSVOX_WINDOWS_MSYS2_SHA256; Toolchain = $ToolchainRoot; NativeCompilation = $false }
}

if (-not (Test-Path $omnivoxRoot)) {
    $name = $pins.EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_ARCHIVE
    $archive = Get-EmacsvoxArchive "$($pins.EMACSVOX_WSL_OMNIVOX_RELEASE_URL)/$name" `
        (Join-Path $CacheDirectory $name) $pins.EMACSVOX_WSL_OMNIVOX_WINDOWS_X64_SHA256
    $stage = "$omnivoxRoot.stage-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force (Split-Path $omnivoxRoot -Parent) | Out-Null
    try {
        Expand-EmacsvoxZip $archive $stage
        foreach ($file in @('omnivox.exe', 'espeak-ng-data\phontab', 'third-party-licenses\THIRD-PARTY-NOTICES.md')) {
            if (-not (Test-Path (Join-Path $stage $file))) { throw "Incomplete verified Omnivox archive: $file" }
        }
        # Move the verified complete archive before executing it: Windows may
        # retain an executable lock briefly after a version probe exits.
        [IO.Directory]::Move($stage, $omnivoxRoot)
        try {
            $version = Invoke-EmacsvoxNative $omnivox @('--version')
            if ($version -ne "omnivox $($pins.EMACSVOX_WSL_OMNIVOX_VERSION)") { throw "Unexpected release version: $version" }
        }
        catch {
            Remove-Item -LiteralPath $omnivoxRoot -Recurse -Force
            throw
        }
    }
    finally { if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
$environment = @{ EMACSVOX_NATIVE_ROOT = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root)); EMACSVOX_NATIVE_BYTECODE = 'build' }
$buildArguments = @('-Q', '--batch', '--eval', (Get-EmacsvoxLoadExpression (Join-Path $root 'utils\emacsvox-native-bytecode.el')), '--funcall', 'emacsvox-native-bytecode-main')
Write-Host 'Rebuilding native Emacsvox byte-code.'
Invoke-EmacsvoxNative $selected.Program $buildArguments $environment (Join-Path $logs 'native-bytecode.log') 1200 | Out-Null
$environment.EMACSVOX_NATIVE_BYTECODE = 'check'
Invoke-EmacsvoxNative $selected.Program $buildArguments $environment (Join-Path $logs 'native-bytecode-check.log') | Out-Null
$config = @{ Schema = 1; Role = $Role; Emacs = $selected.Program; EmacsVersion = $selected.Version;
    Omnivox = $omnivox; OmnivoxVersion = $pins.EMACSVOX_WSL_OMNIVOX_VERSION; Profile = $profile; Logs = $logs;
    ToolchainRoot = $ToolchainRoot; CacheDirectory = $CacheDirectory }
$sourceHashes = @{}
foreach ($file in Get-ChildItem (Join-Path $root 'lisp\*.el') -File) {
    $sourceHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
Write-EmacsvoxJson (Join-Path $logs 'native-install-provenance.json') @{
    Configuration = $config; Sources = $sourceHashes; ReleasePins = $pins;
    WindowsPins = $windowsPins; InstalledUTC = [DateTime]::UtcNow.ToString('o')
}
Write-EmacsvoxJson $configFile $config
if (-not $NoAudioCheck) { & (Join-Path $root 'bin\emacsvox.ps1') -Check }
else { Write-Host 'Audio check skipped. Run bin\emacsvox.ps1 -Check before accepting speech.' }
Write-Host 'Native Windows preview installed. Start it with .\bin\emacsvox.ps1'
