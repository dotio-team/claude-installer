; ============================================================================
;  Claude Code · Dotio one-click installer (Windows)
;  Inno Setup 6.x   —   https://jrsoftware.org/isinfo.php
;
;  Builds a single ClaudeCode-Installer.exe that:
;    1. Checks for Node.js 20 LTS, downloads + installs the official MSI if
;       missing or too old.
;    2. Checks for Git for Windows, downloads + installs if missing.
;    3. Runs `npm install -g @anthropic-ai/claude-code` as the user.
;    4. Handles Korean usernames by detecting non-ASCII in %USERPROFILE%
;       and warning the user (and offering an alternate npm prefix).
;    5. Registers an uninstaller (Settings → Apps → Claude Code).
;
;  Build (on Windows or via GitHub Actions windows-latest):
;    iscc installer.iss
; ============================================================================

#define MyAppName        "Claude Code"
#define MyAppPublisher   "Dotio"
; TODO(next-week): swap back to https://claude-installer.dotio.team once DNS is live
#define MyAppURL         "https://claude-installer-psi.vercel.app"
#define MyAppVersion     GetEnv("APP_VERSION")
#if MyAppVersion == ""
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{C7A18E2E-8B5F-4D0B-A7C9-CC785C000001}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\ClaudeCode
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=resources\license.txt
OutputDir=dist
OutputBaseFilename=ClaudeCode-Installer
; SetupIconFile=resources\app.ico  ; TODO: ship branded icon in v1.1
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
UninstallDisplayName={#MyAppName} (Dotio Installer)
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=no
DisableWelcomePage=no

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
; Pure runtime files: the post-install batch + PATH helper + uninstall helper.
Source: "resources\postinstall.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "resources\ensure-path.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "resources\claude-uninstall.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Claude Code 사용법"; Filename: "{#MyAppURL}"
Name: "{group}\Claude Code 제거"; Filename: "{uninstallexe}"

[Run]
; Run after files copied; ensures Node/Git/claude end up usable in a new shell.
Filename: "{cmd}"; Parameters: "/C ""{app}\postinstall.cmd"""; Flags: runhidden waituntilterminated; StatusMsg: "Claude Code를 설정하고 있습니다... (1~3분 소요)"

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C ""{app}\claude-uninstall.cmd"""; Flags: runhidden

[Code]
const
  REQUIRED_NODE_MAJOR = 18;
  NODE_URL = 'https://nodejs.org/dist/v20.18.1/node-v20.18.1-x64.msi';
  GIT_URL  = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe';

var
  DownloadPage: TDownloadWizardPage;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(
    '의존성을 다운로드하고 있습니다',
    'Node.js와 Git이 필요한 경우에만 다운로드합니다.',
    nil);
end;

function NodeNeedsInstall: Boolean;
var
  ResultCode: Integer;
  TmpFile: String;
  RawVer: AnsiString;   // LoadStringFromFile requires AnsiString in Unicode IS
  NodeVer: String;
  DotPos: Integer;
begin
  Result := True;
  TmpFile := ExpandConstant('{tmp}\node-version.txt');
  if Exec(ExpandConstant('{cmd}'), '/C node -v > "' + TmpFile + '" 2>&1',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if (ResultCode = 0) and LoadStringFromFile(TmpFile, RawVer) then
    begin
      NodeVer := String(RawVer);  // node only emits ASCII for -v, safe cast
      // Strip trailing CR/LF
      StringChangeEx(NodeVer, #13, '', True);
      StringChangeEx(NodeVer, #10, '', True);
      if (Length(NodeVer) >= 4) and (NodeVer[1] = 'v') then
      begin
        DotPos := Pos('.', NodeVer);
        if (DotPos > 2) and
           (StrToIntDef(Copy(NodeVer, 2, DotPos - 2), 0) >= REQUIRED_NODE_MAJOR) then
          Result := False;
      end;
    end;
  end;
end;

function GitNeedsInstall: Boolean;
var
  ResultCode: Integer;
begin
  Result := not Exec(ExpandConstant('{cmd}'), '/C git --version >nul 2>&1',
                    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if not Result then Result := (ResultCode <> 0);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    if NodeNeedsInstall then
      DownloadPage.Add(NODE_URL, 'node-installer.msi', '');
    if GitNeedsInstall then
      DownloadPage.Add(GIT_URL, 'git-installer.exe', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        // Any exception here means the download failed (network error, user
        // cancel, etc). Inno Setup's TExceptionType enum constants aren't
        // exposed to Pascal Script in all versions, so we surface the message
        // unconditionally — SuppressibleMsgBox returns IDOK silently in
        // /SILENT mode, so this won't break unattended installs.
        SuppressibleMsgBox('의존성 다운로드에 실패했습니다. 인터넷 연결을 확인해주세요.' + #13#10 + GetExceptionMessage,
                           mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;

    if Result and NodeNeedsInstall then
    begin
      WizardForm.StatusLabel.Caption := 'Node.js를 설치 중입니다...';
      if not Exec(ExpandConstant('{cmd}'),
                  '/C msiexec /i "' + ExpandConstant('{tmp}\node-installer.msi') + '" /qn /norestart',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      begin
        MsgBox('Node.js 설치 실행에 실패했습니다.', mbCriticalError, MB_OK);
        Result := False;
      end
      else if ResultCode <> 0 then
      begin
        MsgBox('Node.js 설치가 실패했습니다 (코드 ' + IntToStr(ResultCode) + ').',
               mbCriticalError, MB_OK);
        Result := False;
      end;
    end;

    if Result and GitNeedsInstall then
    begin
      WizardForm.StatusLabel.Caption := 'Git을 설치 중입니다...';
      if not Exec(ExpandConstant('{tmp}\git-installer.exe'),
                  '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"',
                  '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      begin
        MsgBox('Git 설치 실행에 실패했습니다.', mbCriticalError, MB_OK);
        Result := False;
      end;
    end;
  end;
end;
