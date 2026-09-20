# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Setup, [switch]$InstallFixture, [string]$ResumeWork)
$ErrorActionPreference = 'Stop'
$fixtureRegistration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D78E9D1F-D616-4B21-9B4D-5D97CD825101}_is1'
if ($InstallFixture -and ((Split-Path $Setup -Leaf) -notlike 'emacsvox-fixture-*-setup.exe' -or
                         (Test-Path $fixtureRegistration) -and -not $ResumeWork)) { throw 'Installation requires an unregistered isolated fixture installer.' }

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
    public static string Value(int handle) {
        IAccessible value = Get(handle);
        try { return value.get_accValue(0); }
        finally { Marshal.ReleaseComObject(value); }
    }
    public static bool Checked(int handle) {
        IAccessible value = Get(handle);
        try { return (Convert.ToInt32(value.get_accState(0)) & 16) != 0; }
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
$work = if ($ResumeWork) { [IO.Path]::GetFullPath($ResumeWork).TrimEnd('\') }
        else { Join-Path $env:TEMP ('evox wizard ' + [guid]::NewGuid().ToString('N').Substring(0,12)) }
if ($ResumeWork -and (-not $InstallFixture -or (Split-Path $work -Parent) -ne $env:TEMP.TrimEnd('\') -or
    (Split-Path $work -Leaf) -notmatch '^evox wizard [a-f0-9]{12}$' -or
    (Get-ItemProperty -LiteralPath $fixtureRegistration).InstallLocation.TrimEnd('\') -ne (Join-Path $work 'not installed'))) {
    throw 'Resume requires this script''s registered isolated fixture.'
}
$destination = Join-Path $work 'not installed'
$env:OMNIVOX_VOICE_ROOT = Join-Path $work 'isolated shared voices'
if (-not $ResumeWork) { New-Item -ItemType Directory $work | Out-Null }
elseif (Test-Path (Join-Path $work 'wizard.log')) {
    Move-Item -LiteralPath (Join-Path $work 'wizard.log') -Destination (Join-Path $work ('wizard-previous-' + [guid]::NewGuid().ToString('N') + '.log'))
}
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
        if ($owned.ContainsKey([int]$window.Current.ProcessId) -and -not $window.Current.IsOffscreen) { return $window }
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
    if ($InstallFixture) {
        Click-Button $window 'Install'
        $deadline = [DateTime]::UtcNow.AddMinutes(12)
        do {
            Start-Sleep -Milliseconds 500
            $window = Find-Window
            $items = if ($window) { @(Controls $window) } else { @() }
            $finished = @($items | Where-Object { $_.Current.Name.Replace('&','') -eq 'Finish' })
        } while (-not $finished.Count -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited)
        if (-not $finished.Count) { throw 'No installation completion page.' }
        $memos = @($items | Where-Object { $_.Current.ClassName -eq 'TNewMemo' })
        if ($memos.Count -ne 1) { throw 'Focusable completion summary missing.' }
        $summary = [WizardAccessibility]::Value($memos[0].Current.NativeWindowHandle)
        [IO.File]::WriteAllText((Join-Path $work 'completion.txt'), $summary)
        if ($summary -notmatch 'is installed' -or $summary -notmatch 'Start menu' -or $summary -notmatch 'uninstall') {
            throw "Incomplete installation instructions: $summary"
        }
        Click-Button $window 'Finish'
        $deadline = [DateTime]::UtcNow.AddMinutes(3)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $null = Find-Window
            foreach ($dialog in $root.FindAll([Windows.Automation.TreeScope]::Children, $trueCondition)) {
                if ($owned.ContainsKey([int]$dialog.Current.ProcessId) -and $dialog.Current.Name -eq 'Emacsvox' -and
                    -not $dialog.Current.IsOffscreen) {
                    $ok = Controls $dialog | Where-Object { $_.Current.Name -eq 'OK' } | Select-Object -First 1
                    if ($ok) { [WizardAccessibility]::Press($ok.Current.NativeWindowHandle, 43) }
                }
            }
        }
        if (-not $process.HasExited) { throw 'Finish actions did not complete.' }
        if ($process.ExitCode -ne 0) { throw 'Installation failed.' }
        $speechResults = @(Get-ChildItem -LiteralPath (Join-Path $destination 'logs') -Filter 'native-startup-*.txt')
        if (-not $speechResults.Count -or @($speechResults | Where-Object { [IO.File]::ReadAllText($_.FullName) -notmatch '^PASS:' }).Count) {
            throw 'The finish-page speech check did not pass.'
        }
        # Fresh native GUI processes exercise automatic onboarding, persistence
        # across restart, and an explicitly opened file. Only fixture profiles
        # and processes participate; the personal installation stays running.
        $current = [IO.File]::ReadAllText((Join-Path $destination 'current.json')) | ConvertFrom-Json
        $application = Join-Path $destination "Applications\$($current.Build)"
        $config = [IO.File]::ReadAllText((Join-Path $application 'native-install.json')) | ConvertFrom-Json
        foreach ($expected in @('speech-check','show','hide','file')) {
            $result = Join-Path $work "welcome-$expected.txt"
            $settings = @{Root=$application;Profile=$config.Profile;Omnivox=$config.Omnivox;Result=$(if ($expected -eq 'speech-check') { $result } else { $null })}
            $environment = @{
                EMACSVOX_NATIVE_SETTINGS=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json)))
                EMACSVOX_WELCOME_TEST_RESULT=$result; EMACSVOX_WELCOME_TEST_EXPECT=$expected
                OMNIVOX_ENGINE='winrt'; TTS_PROGRAM=$config.Omnivox
                EMACSVOX_PLAY=$null; OMNIVOX_AUDIO_OUTPUT=$null; EMACSVOX_NATIVE_RESULT=$null
                ESPEAK_NG_DATA=(Join-Path (Split-Path $config.Omnivox) 'espeak-ng-data')
            }
            $arguments = @('-Q','--no-splash','--name','Emacsvox welcome fixture','--eval',
                (Get-EmacsvoxLoadExpression (Join-Path $PSScriptRoot 'emacsvox-welcome-native-check.el')),
                '--eval',(Get-EmacsvoxLoadExpression (Join-Path $application 'utils\emacsvox-windows-startup.el')))
            if ($expected -eq 'file') {
                [IO.File]::WriteAllText((Join-Path $config.Profile 'emacsvox-welcome-state'), "show`n")
                $file = Join-Path $work 'opened.txt'
                [IO.File]::WriteAllText($file, 'Explicitly opened file must keep focus.')
                $arguments += $file
            }
            try { Invoke-EmacsvoxNative $config.Emacs $arguments $environment -TimeoutSeconds 50 | Out-Null }
            catch { if (Test-Path $result) { Write-Host ([IO.File]::ReadAllText($result)) }; throw }
            if (-not (Test-Path $result) -or [IO.File]::ReadAllText($result) -notmatch '^PASS:') { throw "Welcome acceptance failed: $expected" }
            Write-Host ([IO.File]::ReadAllText($result))
        }
        # Start the actual fixture uninstaller and inspect native checkbox roles.
        $registration = Get-ItemProperty -LiteralPath $fixtureRegistration
        if ($registration.InstallLocation.TrimEnd('\') -ne $destination) { throw 'Wrong fixture registration.' }
        $uninstaller = @(Get-ChildItem -LiteralPath $destination -Filter 'unins*.exe')[0].FullName
        foreach ($category in @('profile','logs','Cache')) {
            $folder = Join-Path $destination $category
            New-Item -ItemType Directory -Force $folder | Out-Null
            [IO.File]::WriteAllText((Join-Path $folder 'cleanup-fixture.txt'), 'remove only when selected')
        }
        $start.FileName = $uninstaller
        $start.Arguments = ConvertTo-NativeArgument ('/LOG=' + (Join-Path $work 'uninstall.log'))
        $process = [Diagnostics.Process]::Start($start)
        $owned[$process.Id] = $process
        $window = $null
        for ($i=0; $i -lt 90; $i++) {
            Start-Sleep -Milliseconds 500
            $window = Find-Window
            if ($window -and $window.Current.Name -match 'personal data') { break }
        }
        if (-not $window -or $window.Current.Name -notmatch 'personal data') { throw 'No cleanup choices dialog.' }
        $items = @(Controls $window)
        $checks = @($items | Where-Object { $_.Current.ClassName -eq 'TNewCheckBox' })
        if ($checks.Count -ne 3) { throw 'Expected three cleanup choices.' }
        foreach ($check in $checks) {
            if ([WizardAccessibility]::Checked($check.Current.NativeWindowHandle)) { throw 'Destructive cleanup was selected by default.' }
            # Exercise only fixture-owned profile and log removal. Shared voice
            # retention and ownership have separate service tests.
            if ($check.Current.Name -notmatch 'shared library') {
                [WizardAccessibility]::Press($check.Current.NativeWindowHandle, 44)
            }
        }
        Click-Button $window 'Continue'
        # Confirm application's removal, then acknowledge cleanup results and
        # Inno's completion message, only in windows owned by this fixture.
        $deadline = [DateTime]::UtcNow.AddMinutes(3)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $null = Find-Window
            foreach ($dialog in $root.FindAll([Windows.Automation.TreeScope]::Children, $trueCondition)) {
                if ($owned.ContainsKey([int]$dialog.Current.ProcessId) -and -not $dialog.Current.IsOffscreen) {
                    $items = @(Controls $dialog)
                    foreach ($item in $items) {
                        if ($item.Current.ClassName -eq 'TNewMemo') {
                            [IO.File]::WriteAllText((Join-Path $work 'cleanup-results.txt'),
                                [WizardAccessibility]::Value($item.Current.NativeWindowHandle))
                        }
                    }
                    $button = $items | Where-Object { $_.Current.Name.Replace('&','') -in @('Yes','OK') } | Select-Object -First 1
                    if ($button) { [WizardAccessibility]::Press($button.Current.NativeWindowHandle, 43) }
                }
            }
        }
        if (-not $process.HasExited -or $process.ExitCode -ne 0) { throw 'Fixture uninstall did not complete.' }
        foreach ($category in @('profile','logs','Cache')) {
            if (Test-Path (Join-Path $destination "$category\cleanup-fixture.txt")) { throw "Selected cleanup retained $category" }
        }
        if (Test-Path $fixtureRegistration) { throw 'Fixture remains registered.' }
        Write-Host 'PASS: accessible completion instructions, finish actions, three unchecked cleanup choices and selected-data uninstall.'
    } else {
    Click-Button $window 'Cancel'
    Start-Sleep -Milliseconds 300
    foreach ($dialog in $root.FindAll([Windows.Automation.TreeScope]::Children, $trueCondition)) {
        if ($owned.ContainsKey([int]$dialog.Current.ProcessId) -and -not $dialog.Current.IsOffscreen) {
            $yes = Controls $dialog | Where-Object { $_.Current.Name.Replace('&','') -eq 'Yes' } | Select-Object -First 1
            if ($yes) { [WizardAccessibility]::Press($yes.Current.NativeWindowHandle, 43) }
        }
    }
    if (-not $process.WaitForExit(15000)) { throw 'Wizard did not close after cancellation.' }
    if (Test-Path $destination) { throw 'Cancelled wizard changed the installation directory.' }
    Write-Host 'PASS: native wizard controls, accessible choices, review page and cancellation before installation.'
    }
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
