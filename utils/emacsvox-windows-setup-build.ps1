# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$StagingDirectory,
    [string]$Compiler = "$env:LOCALAPPDATA\Emacsvox\Toolchains\Inno-7.1.0\ISCC.exe",
    [switch]$InstallCompiler
)
. (Join-Path $PSScriptRoot 'emacsvox-windows-common.ps1')
Assert-NativeWindows
Assert-WindowsLocalPath $StagingDirectory
$pins = Read-EmacsvoxPins (Join-Path $PSScriptRoot '..\etc\windows-setup.conf')
if (-not (Test-Path -LiteralPath $Compiler)) {
    if (-not $InstallCompiler) { throw 'Install the pinned Inno Setup compiler, or pass -InstallCompiler for per-user installation.' }
    $archive = Get-EmacsvoxArchive $pins.EMACSVOX_INNO_URL `
        (Join-Path "$env:LOCALAPPDATA\Emacsvox\Downloads" $pins.EMACSVOX_INNO_ARCHIVE) $pins.EMACSVOX_INNO_SHA256
    $signature = Get-AuthenticodeSignature -LiteralPath $archive
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Pyrsys B\.V\.') {
        throw 'The pinned Inno Setup compiler installer has no valid expected publisher signature.'
    }
    Invoke-EmacsvoxNative $archive @('/CURRENTUSER','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',
        '/NOICONS',('/DIR=' + (Split-Path $Compiler -Parent))) -TimeoutSeconds 300 | Out-Null
}
$version = Invoke-EmacsvoxNative $Compiler @('--version')
if ($version -notmatch ('^' + [regex]::Escape($pins.EMACSVOX_INNO_VERSION) + '([.]0)?$')) {
    throw "Unexpected Inno Setup compiler version: $version"
}
Invoke-EmacsvoxNative $Compiler @('--quiet-progress', '--no-ide-signtools', (Join-Path $StagingDirectory 'setup.iss')) `
    -Log (Join-Path $StagingDirectory 'compile.log') -TimeoutSeconds 1200 | Out-Null
$outputs = @(Get-ChildItem -LiteralPath (Join-Path $StagingDirectory 'output') -Filter '*-setup.exe' -File)
if ($outputs.Count -ne 1) { throw 'Expected exactly one development setup executable.' }
$output = $outputs[0].FullName
$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$output.sha256", "$hash  $($outputs[0].Name)`n")
Write-EmacsvoxJson "$output.provenance.json" @{
    Schema=1; Kind='development'; CompilerVersion=$version;
    CompilerSHA256=(Get-FileHash -LiteralPath $Compiler -Algorithm SHA256).Hash.ToLowerInvariant();
    ManifestSHA256=(Get-FileHash -LiteralPath (Join-Path $StagingDirectory 'setup-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();
    InstallerSHA256=$hash
}
Write-Host "Development installer: $output"
