@echo off
:: postinstall.cmd — runs after Inno Setup copies files and after Node + Git
:: have been installed (if they were missing). Final job: install
:: @anthropic-ai/claude-code globally, handle Korean usernames, smoke test.
::
:: Output goes to %TEMP%\claude-installer.log AND %APPDATA%\ClaudeInstaller\install.log
:: so the user can find it later without admin rights.

setlocal EnableDelayedExpansion
set "LOGDIR=%APPDATA%\ClaudeInstaller"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" 2>nul
set "LOG=%LOGDIR%\install.log"
set "SYSLOG=%TEMP%\claude-installer.log"

call :log "==== Claude Code postinstall starting ===="
call :log "USERPROFILE=%USERPROFILE%  USERNAME=%USERNAME%"

:: Inno Setup just installed Node/Git via MSI in admin context, but PATH for
:: THIS process was set before that. Bring the just-installed bins in scope.
set "PATH=%ProgramFiles%\nodejs;%ProgramFiles%\Git\cmd;%PATH%"

:: --- 1. Verify Node ---------------------------------------------------------
where node >nul 2>&1
if errorlevel 1 (
  call :log "ERROR: node not on PATH after install"
  call :err "Node.js 설치 후에도 node 명령을 찾지 못했습니다. 컴퓨터를 재시작한 뒤 다시 시도해주세요."
  exit /b 1
)
for /f "delims=" %%v in ('node -v 2^>nul') do set "NODE_V=%%v"
call :log "node %NODE_V%"

:: --- 2. Verify Git ----------------------------------------------------------
where git >nul 2>&1
if errorlevel 1 (
  call :log "ERROR: git not on PATH after install"
  call :err "Git 설치 후에도 git 명령을 찾지 못했습니다. 컴퓨터를 재시작한 뒤 다시 시도해주세요."
  exit /b 1
)
for /f "delims=" %%v in ('git --version 2^>nul') do set "GIT_V=%%v"
call :log "git: %GIT_V%"

:: --- 3. Korean username detection ------------------------------------------
:: A Hangul %USERPROFILE% can break some npm postinstall scripts that
:: shell out with the wrong code page. If detected, point the global npm
:: prefix at C:\Users\Public\claude-code\ which is always ASCII-safe.
echo %USERPROFILE% | findstr /R "[^a-zA-Z0-9_:.\\ \-]" >nul
if not errorlevel 1 (
  set "SAFE_PREFIX=C:\Users\Public\claude-code"
  if not exist "!SAFE_PREFIX!" mkdir "!SAFE_PREFIX!" >nul 2>&1
  call :log "Non-ASCII USERPROFILE detected -> using safe npm prefix !SAFE_PREFIX!"
  call npm config set prefix "!SAFE_PREFIX!" --global >>"%LOG%" 2>&1
  setx PATH "%PATH%;!SAFE_PREFIX!" >nul
  :: Reflect for this session too
  set "PATH=%PATH%;!SAFE_PREFIX!"
)

:: --- 4. Install claude-code ------------------------------------------------
:: --unsafe-perm matches the macOS side: ensures post-install scripts run so
:: the platform-native binary actually downloads. Without it `claude` ends
:: up on PATH but errors with "native binary not installed".
call :log "Running npm install -g --unsafe-perm @anthropic-ai/claude-code..."
call npm install -g --unsafe-perm @anthropic-ai/claude-code >>"%LOG%" 2>&1
if errorlevel 1 (
  call :log "ERROR: npm install failed"
  call :err "Claude Code 설치에 실패했습니다. 인터넷 연결과 회사 프록시 설정을 확인해주세요."
  exit /b 1
)

:: --- 5. Smoke test ---------------------------------------------------------
where claude >nul 2>&1
if errorlevel 1 (
  call :log "WARN: claude command not on PATH yet — needs a new terminal"
  goto :smoke_done
)
:: Run --version and confirm it returns a real version string (not just
:: prints "native binary not installed").
for /f "delims=" %%v in ('claude --version 2^>^&1') do set "CLAUDE_V=%%v"
echo !CLAUDE_V! | findstr /i /r "claude.*[0-9][0-9]*\.[0-9]" >nul
if errorlevel 1 (
  call :log "WARN: claude --version unexpected output: !CLAUDE_V!"
) else (
  call :log "smoke test passed: !CLAUDE_V!"
)
:smoke_done

call :log "==== Postinstall finished OK ===="
exit /b 0

:log
  >>"%LOG%"    echo [%date% %time%] %~1
  >>"%SYSLOG%" echo [%date% %time%] %~1
  goto :eof

:err
  call :log "USER_VISIBLE: %~1"
  powershell -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('%~1','Claude Code 인스톨러','OK','Error') | Out-Null" >nul 2>&1
  goto :eof
