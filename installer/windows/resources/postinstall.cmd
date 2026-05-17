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
:: --unsafe-perm + --foreground-scripts mirror the macOS side: the first
:: lets the install.cjs post-script (which downloads the platform-native
:: binary) execute when running as Administrator; the second surfaces its
:: output in the log so we can tell when it silently failed.
call :log "npm install -g --unsafe-perm --foreground-scripts @anthropic-ai/claude-code (try 1)"
call npm install -g --unsafe-perm --foreground-scripts --no-audit --no-fund @anthropic-ai/claude-code >>"%LOG%" 2>&1
if errorlevel 1 (
  call :log "ERROR: npm install failed (try 1)"
  call :err "Claude Code 설치에 실패했습니다. 인터넷 연결과 회사 프록시 설정을 확인해주세요."
  exit /b 1
)

:: --- 5. Smoke test + one auto-repair attempt -------------------------------
call :smoke
if !SMOKE_OK!==1 goto :smoke_done

call :log "smoke fail; attempting auto-repair (uninstall + reinstall)"
call npm uninstall -g @anthropic-ai/claude-code >>"%LOG%" 2>&1
call npm install -g --unsafe-perm --foreground-scripts --no-audit --no-fund @anthropic-ai/claude-code >>"%LOG%" 2>&1
call :smoke
if !SMOKE_OK!==1 goto :smoke_done

:: Final fallback — leave the user a clear path forward.
call :log "WARN: native binary still missing after auto-repair"
call :err "Claude Code 패키지는 설치되었지만 플랫폼 전용 바이너리 다운로드에 실패했습니다.\n\nPowerShell을 관리자 권한으로 열고 아래를 실행해주세요:\nnpm install -g --unsafe-perm --foreground-scripts @anthropic-ai/claude-code"
goto :smoke_done

:smoke
  set "SMOKE_OK=0"
  where claude >nul 2>&1
  if errorlevel 1 (
    call :log "WARN: claude not on PATH yet — needs a new terminal"
    goto :eof
  )
  for /f "delims=" %%v in ('claude --version 2^>^&1') do set "CLAUDE_V=%%v"
  echo !CLAUDE_V! | findstr /r "[0-9][0-9]*\.[0-9][0-9]*\.[0-9]" >nul
  if errorlevel 1 (
    call :log "smoke fail: !CLAUDE_V!"
  ) else (
    call :log "smoke ok: !CLAUDE_V!"
    set "SMOKE_OK=1"
  )
  goto :eof

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
