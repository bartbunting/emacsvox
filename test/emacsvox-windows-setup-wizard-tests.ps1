# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Setup)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Accessibility;
public static class WizardAccessibility {
    [DllImport("oleacc.dll")]
    private static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint objectId, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IAccessible accessible);
    public static IAccessible Get(int handle) {
        Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
        IAccessible value;
        Marshal.ThrowExceptionForHR(AccessibleObjectFromWindow(new IntPtr(handle), 0xFFFFFFFC, ref iid, out value));
        return value;
    }
    public static string Describe(int handle) {
        IAccessible value = Get(handle);
        try { return value.get_accName(0) + " | role=" + value.get_accRole(0) + " | state=" + value.get_accState(0); }
        finally { Marshal.ReleaseComObject(value); }
    }
    public static void Press(int handle, int expectedRole) {
        IAccessible value = Get(handle);
        try {
            int state = Convert.ToInt32(value.get_accState(0));
            if (Convert.ToInt32(value.get_accRole(0)) != expectedRole || (state & 1) != 0 ||
                (state & 0x100000) == 0 || String.IsNullOrEmpty(value.get_accName(0)))
                throw new InvalidOperationException("Named, focusable, enabled accessible control missing");
            value.accDoDefaultAction(0);
        } finally { Marshal.ReleaseComObject(value); }
    }
}
'@
$work = Join-Path $env:TEMP ('evox wizard ' + [guid]::NewGuid().ToString('N').Substring(0,12))
$destination = Join-Path $work 'not installed'
New-Item -ItemType Directory $work | Out-Null
. (Join-Path $PSScriptRoot '..\utils\emacsvox-windows-common.ps1')
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $Setup
$start.Arguments = (@('/SP-',('/DIR=' + $destination),('/LOG=' + (Join-Path $work 'wizard.log'))) |
    ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
$start.UseShellExecute = $false
$process = [Diagnostics.Process]::Start($start)
$owned = @{ $process.Id=$process }
$root = [Windows.Automation.AutomationElement]::RootElement
$trueCondition = [Windows.Automation.Condition]::TrueCondition
function Find-Window {
    foreach ($child in Get-CimInstance Win32_Process) {
        if ($owned.ContainsKey([int]$child.ParentProcessId) -and -not $owned[[int]$child.ParentProcessId].HasExited -and
            -not $owned.ContainsKey([int]$child.ProcessId)) {
            $ownedProcess = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
            if ($ownedProcess) {
                $null = $ownedProcess.Handle
                $owned[[int]$child.ProcessId] = $ownedProcess
            }
        }
    }
    foreach ($window in $root.FindAll([Windows.Automation.TreeScope]::Children, $trueCondition)) {
        if ($owned.ContainsKey($window.Current.ProcessId) -and -not $window.Current.IsOffscreen) { return $window }
    }
    return $null
}
function Controls($Window) {
    @($Window.FindAll([Windows.Automation.TreeScope]::Descendants, $trueCondition) |
        Where-Object { -not $_.Current.IsOffscreen })
}
function Click-Button($Window, [string]$Name) {
    $button = Controls $Window | Where-Object {
        $_.Current.Name.Replace('&','').TrimEnd(' ', '>') -eq $Name.TrimEnd(' ', '>')
    } | Select-Object -First 1
    if (-not $button -or -not $button.Current.IsEnabled) {
        throw "Accessible enabled button missing: $Name"
    }
    # Delphi controls expose MSAA roles/actions even where this .NET UIA client
    # reports only a generic window. Verify the accessibility contract itself.
    [WizardAccessibility]::Press($button.Current.NativeWindowHandle, 43)
    Start-Sleep -Milliseconds 350
}
try {
    $window = $null
    for ($i=0; $i -lt 30 -and -not $window; $i++) { Start-Sleep -Milliseconds 500; $window = Find-Window }
    if (-not $window) { throw 'The setup wizard did not appear.' }
    $pages = @()
    # Welcome, licence, information, destination, tasks, then ready-to-install.
    for ($page=0; $page -lt 6; $page++) {
        $items = Controls $window
        $names = @($items | ForEach-Object { $_.Current.Name } | Where-Object { $_ })
        $pages += @{ Page=$page; Window=$window.Current.Name; Names=$names; Controls=@($items | ForEach-Object {
            @{ Name=$_.Current.Name; Type=$_.Current.ControlType.ProgrammaticName;
               Class=$_.Current.ClassName; Patterns=@($_.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName });
               MSAA=$(try { [WizardAccessibility]::Describe($_.Current.NativeWindowHandle) } catch { $_.Exception.Message });
               Focusable=$_.Current.IsKeyboardFocusable; Enabled=$_.Current.IsEnabled }
        }) }
        Write-EmacsvoxJson (Join-Path $work 'accessible-pages.json') $pages
        if ($page -eq 1) {
            $accept = $items | Where-Object { $_.Current.Name.Replace('&','') -eq 'I accept the agreement' } | Select-Object -First 1
            if (-not $accept) { throw 'Accessible licence choice missing.' }
            [WizardAccessibility]::Press($accept.Current.NativeWindowHandle, 45)
        }
        if ($page -lt 5) { Click-Button $window 'Next >' }
        elseif (-not ($names -match 'Ready to Install')) { throw 'Wizard did not reach the review page.' }
    }
    Write-EmacsvoxJson (Join-Path $work 'accessible-pages.json') $pages
    Click-Button $window 'Cancel'
    Start-Sleep -Milliseconds 300
    foreach ($dialog in $root.FindAll([Windows.Automation.TreeScope]::Children, $trueCondition)) {
        if ($owned.ContainsKey($dialog.Current.ProcessId) -and -not $dialog.Current.IsOffscreen) {
            $yes = Controls $dialog | Where-Object { $_.Current.Name.Replace('&','') -eq 'Yes' } | Select-Object -First 1
            if ($yes) { [WizardAccessibility]::Press($yes.Current.NativeWindowHandle, 43) }
        }
    }
    if (-not $process.WaitForExit(15000)) { throw 'Wizard did not close after cancellation.' }
    if (Test-Path $destination) { throw 'Cancelled wizard changed the installation directory.' }
    Write-Host 'PASS: native wizard controls, accessible choices, review page and cancellation before installation.'
    Write-Host 'Screen-reader listening and keyboard-only acceptance remain separate checks.'
}
finally {
    # These are only the setup processes started by this test; no Emacs or
    # unrelated windows are touched. Terminate a failed test's wizard.
    foreach ($child in $owned.Values) {
        if (-not $child.HasExited) { $child.Kill() }
        $child.Dispose()
    }
    Write-Host "Wizard evidence: $work"
}
