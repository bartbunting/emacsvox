# Copyright (C) 2026 Emacsvox Contributors
# SPDX-License-Identifier: GPL-2.0-or-later

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$CommonSource,
    [Parameter(Mandatory = $true)]
    [string]$LauncherSource,
    [Parameter(Mandatory = $true)]
    [string]$HangingSource
)

$ErrorActionPreference = "Stop"
$Compiler = Join-Path $env:WINDIR `
    "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path $Compiler)) {
    exit 77
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
& $Compiler /nologo /target:exe /optimize+ `
    "/out:$OutputDirectory\HangingBridge.exe" $HangingSource
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& $Compiler /nologo /target:exe /optimize+ `
    "/out:$OutputDirectory\TimeoutLauncher.exe" `
    $LauncherSource $CommonSource
exit $LASTEXITCODE
