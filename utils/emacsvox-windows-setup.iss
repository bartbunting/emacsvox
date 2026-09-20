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
Source: "payload\*"; DestDir: "{app}"; Excludes: "Launcher\*,Setup\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "setup-owner.json"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall
; External source expansion propagates errors to Inno's installation rollback.
; BeforeInstall/AfterInstall exceptions alone are caught and ignored by Inno.
Source: "{code:ConfiguredManifest}"; DestDir: "{app}\Manifests"; DestName: "{#Build}.json"; Flags: external ignoreversion; ExternalSize: 0; BeforeInstall: ConfigureApplication
; Preserve the working launcher and helpers until configuration has succeeded.
Source: "payload\Launcher\*"; DestDir: "{app}\Launcher"; Flags: ignoreversion
Source: "payload\Setup\*"; DestDir: "{app}\Setup"; Flags: ignoreversion

[Icons]
Name: "{group}\Emacsvox Windows Development"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"
Name: "{group}\Check speech"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NoExit -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check"; WorkingDir: "{app}"
Name: "{group}\Uninstall Emacsvox Windows Development"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Emacsvox Windows Development"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check -ShowErrors"; Description: "Test &speech (two short announcements)"; Flags: postinstall skipifsilent; Check: InstallationActivated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; Description: "&Start Emacsvox"; Flags: postinstall unchecked skipifsilent nowait; Check: InstallationActivated

#include "setup-generated-uninstall.iss"

[Code]
var
  ConfigurationAttempted, Activated: Boolean;
  ConfigurationError, ActivationError: String;

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
begin
  ConfigurationAttempted := True;
  ConfigurationError := 'Emacsvox configuration did not complete.';
  WizardForm.StatusLabel.Caption := 'Preparing Emacsvox for your Emacs. This can take a few minutes...';
  try
    ConfigurationError := RunHelper('Configure', ExpandConstant('{tmp}\emacsvox-windows-setup-helper.ps1'),
      ExpandConstant('{tmp}\setup-manifest.json'));
  except
    ConfigurationError := GetExceptionMessage;
  end;
end;

function ConfiguredManifest(Param: String): String;
begin
  { Inno also expands this source while planning, before BeforeInstall runs. }
  if ConfigurationAttempted and (ConfigurationError <> '') then RaiseException(ConfigurationError);
  Result := ExpandConstant('{tmp}\setup-manifest.json');
end;

function InstallationActivated: Boolean;
begin
  Result := Activated;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    try
      ActivationError := RunHelper('Activate', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'),
        ExpandConstant('{app}\Manifests\{#Build}.json'));
    except
      ActivationError := GetExceptionMessage;
    end;
    Activated := ActivationError = '';
    if not Activated then SuppressibleMsgBox(ActivationError, mbError, MB_OK, IDOK);
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if ActivationError <> '' then Result := 1;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and (ActivationError <> '') then begin
    WizardForm.FinishedHeadingLabel.Caption := 'Emacsvox could not be activated';
    WizardForm.FinishedLabel.Caption := ActivationError + #13#10#13#10 +
      'Your previous selection is unchanged. Fix the reported problem and run Setup again.';
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
