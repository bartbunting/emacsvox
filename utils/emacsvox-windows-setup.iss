; Copyright (C) 2026 Emacsvox contributors
; SPDX-License-Identifier: GPL-2.0-or-later
#include "setup-inputs.iss"

[Setup]
AppId={{B2C8A798-1699-456B-8A64-A6D02C347972}
AppName=Emacsvox Windows Development
AppVersion={#AppVersion}
AppVerName=Emacsvox Windows Development {#Build}
AppPublisher=Emacsvox contributors
AppPublisherURL=https://github.com/bartbunting/emacsvox
DefaultDirName={localappdata}\Emacsvox\Desktop Dev
DefaultGroupName=Emacsvox Windows Development
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
WizardStyle=modern
WizardResizable=yes
DisableWelcomePage=no
DisableProgramGroupPage=yes
DisableDirPage=no
UsePreviousAppDir=yes
CloseApplications=no
RestartApplications=no
AllowNoIcons=yes
SetupLogging=yes
UninstallDisplayIcon={app}\{#EmacsDirectory}\bin\emacs.exe
OutputDir=output
OutputBaseFilename=emacsvox-{#Build}-windows-x64-setup
Compression=lzma2/fast
SolidCompression=yes
LicenseFile=payload\Applications\{#Build}\COPYING
InfoBeforeFile=setup-readme.txt

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; Preflight tools appear first so extracting them does not decompress Emacs.
Source: "payload\Setup\emacsvox-windows-common.ps1"; Flags: dontcopy
Source: "payload\Setup\emacsvox-windows-setup-helper.ps1"; Flags: dontcopy
Source: "setup-manifest.json"; Flags: dontcopy
Source: "payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "setup-owner.json"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall
Source: "setup-manifest.json"; DestDir: "{app}\Manifests"; DestName: "{#Build}.json"; Flags: ignoreversion; AfterInstall: ConfigureApplication

[Icons]
Name: "{group}\Emacsvox Windows Development"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"
Name: "{group}\Check speech"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NoExit -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check"; WorkingDir: "{app}"
Name: "{group}\Uninstall Emacsvox Windows Development"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Emacsvox Windows Development"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check -ShowErrors"; Description: "Test &speech (two short announcements)"; Flags: postinstall skipifsilent
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; Description: "&Start Emacsvox"; Flags: postinstall unchecked skipifsilent nowait

#include "setup-generated-uninstall.iss"

[Code]
function RunHelper(Action, Helper, Manifest: String): String;
var
  ExitCode: Integer;
  ErrorPath, Arguments: String;
  ErrorText: AnsiString;
begin
  ErrorPath := ExpandConstant('{tmp}\emacsvox-setup-error.txt');
  DeleteFile(ErrorPath);
  Arguments := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + Helper +
    '" -Action ' + Action + ' -InstallRoot "' + ExpandConstant('{app}') +
    '" -ErrorFile "' + ErrorPath + '"';
  if Manifest <> '' then Arguments := Arguments + ' -Manifest "' + Manifest + '"';
  Result := '';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then begin
    if LoadStringFromFile(ErrorPath, ErrorText) then Result := UTF8Decode(ErrorText)
    else Result := 'Emacsvox preparation failed. See the Setup log and the logs folder in the installation directory.';
    Log(Result);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ExtractTemporaryFile('emacsvox-windows-common.ps1');
  ExtractTemporaryFile('emacsvox-windows-setup-helper.ps1');
  ExtractTemporaryFile('setup-manifest.json');
  Result := RunHelper('Preflight', ExpandConstant('{tmp}\emacsvox-windows-setup-helper.ps1'),
    ExpandConstant('{tmp}\setup-manifest.json'));
end;

procedure ConfigureApplication;
var Error: String;
begin
  WizardForm.StatusLabel.Caption := 'Preparing Emacsvox for your Emacs. This can take a few minutes...';
  Error := RunHelper('Configure', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'),
    ExpandConstant('{app}\Manifests\{#Build}.json'));
  if Error <> '' then RaiseException(Error);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Error: String;
begin
  if CurStep = ssPostInstall then begin
    Error := RunHelper('Activate', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'),
      ExpandConstant('{app}\Manifests\{#Build}.json'));
    if Error <> '' then RaiseException(Error);
  end;
end;

function InitializeUninstall: Boolean;
var Error: String;
begin
  Error := RunHelper('UninstallCheck', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'), '');
  Result := Error = '';
  if not Result then SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
end;

procedure InitializeUninstallProgressForm;
begin
  UninstallProgressForm.PageDescriptionLabel.Caption :=
    'Removing application files. Your profile, logs and downloaded voices will be kept.';
end;
