# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([switch]$Check, [switch]$Diagnose, [switch]$ShowErrors)
$ErrorActionPreference = 'Stop'
try {
    $root = Split-Path $PSScriptRoot -Parent
    $current = [IO.File]::ReadAllText((Join-Path $root 'current.json')) | ConvertFrom-Json
    if ($current.Schema -ne 1 -or $current.Product -ne 'Emacsvox.Native.Development.1' -or
        $current.Build -notmatch '^\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}$') { throw 'The installation is incomplete. Run Setup again.' }
    & (Join-Path $root "Applications\$($current.Build)\bin\emacsvox.ps1") -Check:$Check -Diagnose:$Diagnose
}
catch {
    $message = "Emacsvox could not start.`r`n`r`n" + $_.Exception.Message
    if ($Check -or $Diagnose) { Write-Error $message -ErrorAction Continue }
    if ($ShowErrors -or (-not $Check -and -not $Diagnose)) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($message, 'Emacsvox', 'OK', 'Error') | Out-Null
    }
    exit 1
}
