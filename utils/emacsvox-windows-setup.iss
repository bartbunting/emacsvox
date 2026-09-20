; Copyright (C) 2026 Emacsvox contributors
; SPDX-License-Identifier: GPL-2.0-or-later
#include "setup-inputs.iss"

[Setup]
AppId={{B2C8A798-1699-456B-8A64-A6D02C347972}
AppName=Emacsvox Windows
AppVersion={#AppVersion}
AppVerName=Emacsvox {#AppVersion} for Windows
AppPublisher=Emacsvox contributors
AppPublisherURL=https://github.com/bartbunting/emacsvox
DefaultDirName={localappdata}\Emacsvox\Desktop Dev
DefaultGroupName=Emacsvox Windows
UsePreviousGroup=no
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

[Messages]
WelcomeLabel1=Welcome to Emacsvox {#AppVersion} for Windows
WelcomeLabel2=Setup will install Emacs {#EmacsVersion}, Omnivox {#OmnivoxVersion} and Emacsvox {#AppVersion} for your Windows account.%n%nNo administrator privileges or internet connection are needed.%n%nIf you are updating or repairing this installation, close its Emacsvox window first.
FinishedHeadingLabel=Emacsvox {#AppVersion} is installed
FinishedLabel=Start it from the Start menu: search for Emacsvox Windows. A desktop shortcut is optional.%n%nTo uninstall, use Windows Settings > Apps > Installed apps > Emacsvox Windows, or Uninstall Emacsvox Windows in the Start menu.%n%nChoose the actions below, then Finish to run them and close Setup.

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
Name: "{group}\Emacsvox Windows"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"
Name: "{group}\Check speech"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NoExit -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check"; WorkingDir: "{app}"
Name: "{group}\Uninstall Emacsvox Windows"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Emacsvox Windows"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; IconFilename: "{app}\{#EmacsDirectory}\bin\emacs.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"" -Check -ShowErrors"; Description: "Test &speech (two short announcements)"; Flags: postinstall skipifsilent; Check: InstallationActivated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Launcher\Start.ps1"""; Description: "&Start Emacsvox"; Flags: postinstall unchecked skipifsilent nowait; Check: InstallationActivated

#include "setup-generated-uninstall.iss"

[Code]
var
  ConfigurationAttempted, Activated: Boolean;
  ConfigurationError, ActivationError: String;
  FinishSummary: TNewMemo;
  CleanupLogs, CleanupProfile, CleanupVoices: Boolean;
  CleanupReport: String;

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
  if (Action = 'CleanupReview') or (Action = 'Cleanup') then
    Arguments := Arguments + ' -ResultFile "' + ExpandConstant('{tmp}\emacsvox-cleanup.txt') + '"';
  if Action = 'Cleanup' then begin
    if CleanupLogs then Arguments := Arguments + ' -RemoveLogs';
    if CleanupProfile then Arguments := Arguments + ' -RemoveProfile';
    if CleanupVoices then Arguments := Arguments + ' -RemoveVoices';
  end;
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
  if (CurPageID = wpFinished) and (ActivationError = '') then begin
    { A focusable, read-only summary can be reviewed with a screen reader. }
    if FinishSummary = nil then begin
      FinishSummary := TNewMemo.Create(WizardForm);
      FinishSummary.Parent := WizardForm.FinishedPage;
      FinishSummary.SetBounds(WizardForm.FinishedLabel.Left, WizardForm.FinishedLabel.Top,
        WizardForm.FinishedLabel.Width, WizardForm.FinishedLabel.Height);
      FinishSummary.ReadOnly := True;
      FinishSummary.ScrollBars := ssVertical;
      FinishSummary.TabOrder := 0;
    end;
    FinishSummary.Text := 'Emacsvox {#AppVersion} is installed.' + #13#10#13#10 +
      SetupMessage(msgFinishedLabel);
    WizardForm.FinishedLabel.Visible := False;
    WizardForm.ActiveControl := FinishSummary;
  end;
  if (CurPageID = wpFinished) and (ActivationError <> '') then begin
    WizardForm.FinishedHeadingLabel.Caption := 'Emacsvox could not be activated';
    WizardForm.FinishedLabel.Caption := ActivationError + #13#10#13#10 +
      'Your previous selection is unchanged. Fix the reported problem and run Setup again.';
  end;
end;

function CleanupDialog(Review: Boolean; Text: String): Boolean;
var
  Form: TSetupForm;
  Memo: TNewMemo;
  Logs, Profile, Voices: TNewCheckBox;
  OK, Cancel: TNewButton;
begin
  Form := CreateCustomForm(ScaleX(540), ScaleY(430), False, False);
  try
    if Review then Form.Caption := 'Uninstall Emacsvox Windows: personal data'
    else Form.Caption := 'Emacsvox personal data cleanup results';
    Memo := TNewMemo.Create(Form);
    Memo.Parent := Form;
    Memo.SetBounds(ScaleX(12), ScaleY(12), ScaleX(516), ScaleY(255));
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssVertical;
    Memo.Text := Text;
    if Review then begin
      Logs := TNewCheckBox.Create(Form);
      Logs.Parent := Form;
      Logs.SetBounds(ScaleX(12), ScaleY(278), ScaleX(516), ScaleY(24));
      Logs.Caption := 'Remove this installation''s &logs and cached downloads';
      Profile := TNewCheckBox.Create(Form);
      Profile.Parent := Form;
      Profile.SetBounds(ScaleX(12), ScaleY(310), ScaleX(516), ScaleY(24));
      Profile.Caption := 'Remove this installation''s Emacs &profile and welcome preference';
      Voices := TNewCheckBox.Create(Form);
      Voices.Parent := Form;
      Voices.SetBounds(ScaleX(12), ScaleY(342), ScaleX(516), ScaleY(24));
      Voices.Caption := 'Remove &unused downloaded voices from the shared library';
    end;
    OK := TNewButton.Create(Form);
    OK.Parent := Form;
    OK.SetBounds(ScaleX(316), ScaleY(390), ScaleX(100), ScaleY(25));
    if Review then OK.Caption := '&Continue' else OK.Caption := '&OK';
    OK.ModalResult := mrOK;
    OK.Default := True;
    Cancel := TNewButton.Create(Form);
    Cancel.Parent := Form;
    Cancel.SetBounds(ScaleX(428), ScaleY(390), ScaleX(100), ScaleY(25));
    Cancel.Caption := 'Cancel';
    Cancel.ModalResult := mrCancel;
    Cancel.Cancel := True;
    Cancel.Visible := Review;
    Form.ActiveControl := Memo;
    Result := Form.ShowModal = mrOK;
    if Review and Result then begin
      CleanupLogs := Logs.Checked;
      CleanupProfile := Profile.Checked;
      CleanupVoices := Voices.Checked;
    end;
  finally
    Form.Free;
  end;
end;

function ReadCleanupReport: String;
var Text: AnsiString;
begin
  Result := '';
  if LoadStringFromFile(ExpandConstant('{tmp}\emacsvox-cleanup.txt'), Text) then
    Result := UTF8Decode(Text);
end;

function InitializeUninstall: Boolean;
var Error: String;
begin
  Error := RunHelper('UninstallCheck', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'), '');
  Result := Error = '';
  if not Result then begin
    SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
    Exit;
  end;
  { Unattended uninstall always preserves personal data. }
  if not UninstallSilent then begin
    Error := RunHelper('CleanupReview', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'), '');
    if Error <> '' then begin
      SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
      Result := False;
    end else Result := CleanupDialog(True, ReadCleanupReport);
  end;
end;

procedure InitializeUninstallProgressForm;
begin
  UninstallProgressForm.PageDescriptionLabel.Caption :=
    'Removing Emacsvox. Personal data is kept unless you selected cleanup.';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Error: String;
begin
  if CurUninstallStep = usUninstall then begin
    { Recheck after the confirmation dialog, before any deletion. }
    Error := RunHelper('UninstallCheck', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'), '');
    if Error <> '' then begin
      SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
      Abort;
    end;
    if CleanupLogs or CleanupProfile or CleanupVoices then begin
      Error := RunHelper('Cleanup', ExpandConstant('{app}\Setup\emacsvox-windows-setup-helper.ps1'), '');
      if Error <> '' then begin
        SuppressibleMsgBox(Error, mbError, MB_OK, IDOK);
        Abort;
      end;
      CleanupReport := ReadCleanupReport;
      Log(CleanupReport);
    end;
  end;
  if (CurUninstallStep = usPostUninstall) and (CleanupReport <> '') then
    CleanupDialog(False, CleanupReport);
end;
