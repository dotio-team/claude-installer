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
:: THIS process was set before that. Bring the just-installed bins in scope,
:: plus %APPDATA%\npm where npm will drop the claude shims (without it the
:: smoke test below can never see claude and always fired the auto-repair).
set "PATH=%ProgramFiles%\nodejs;%ProgramFiles%\Git\cmd;%APPDATA%\npm;%PATH%"
:: Directory that will hold the claude shims; switched to the safe prefix
:: below when the username is non-ASCII.
set "NPM_BIN=%APPDATA%\npm"

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
:: (findstr can't express this check: it splits patterns on spaces and treats
:: backslashes as escapes, so the old regex never matched reliably.)
powershell -NoProfile -Command "exit [int]($env:USERPROFILE -match '[^\x00-\x7F]')" >nul 2>&1
if errorlevel 1 (
  set "SAFE_PREFIX=C:\Users\Public\claude-code"
  if not exist "!SAFE_PREFIX!" mkdir "!SAFE_PREFIX!" >nul 2>&1
  call :log "Non-ASCII USERPROFILE detected -> using safe npm prefix !SAFE_PREFIX!"
  call npm config set prefix "!SAFE_PREFIX!" --global >>"%LOG%" 2>&1
  set "NPM_BIN=!SAFE_PREFIX!"
  :: Reflect for this session too; the user PATH is persisted in step 6.
  set "PATH=!PATH!;!SAFE_PREFIX!"
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

:: --- 6. Ensure the shim dir is on the *user* PATH ---------------------------
:: setx is the wrong tool for this: it writes the merged process PATH
:: (machine + user) into HKCU and silently truncates at 1024 chars, so the
:: npm dir appended at the end is exactly what got cut off on machines with
:: a long PATH. ensure-path.ps1 appends just the one entry and broadcasts
:: WM_SETTINGCHANGE so freshly opened terminals pick it up.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure-path.ps1" -PathEntry "!NPM_BIN!" >>"%LOG%" 2>&1
if errorlevel 1 (
  call :log "WARN: ensure-path.ps1 failed; user PATH may need a manual entry for !NPM_BIN!"
) else (
  call :log "user PATH ensured: !NPM_BIN!"
)

:: --- 7. Make claude run in PowerShell, not just cmd -------------------------
:: npm generates three shims: claude, claude.cmd, claude.ps1. PowerShell
:: resolves the .ps1 first, and the Windows client default execution policy
:: (Restricted) refuses to load it — so the very first `claude` typed into
:: PowerShell fails even though the install is fine. Two-part fix:
::   a) delete the .ps1 shim so PowerShell falls back to claude.cmd
::   b) if the effective policy is Restricted, relax CurrentUser to
::      RemoteSigned so shims regenerated by a future npm update still work
if exist "!NPM_BIN!\claude.ps1" (
  del /f /q "!NPM_BIN!\claude.ps1" >nul 2>&1
  call :log "Removed claude.ps1 shim (PowerShell now resolves claude.cmd)"
)
set "PS_POLICY="
for /f "delims=" %%p in ('powershell -NoProfile -Command "Get-ExecutionPolicy" 2^>nul') do set "PS_POLICY=%%p"
call :log "PowerShell execution policy: !PS_POLICY!"
if /i "!PS_POLICY!"=="Restricted" (
  powershell -NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force" >>"%LOG%" 2>&1
  call :log "Relaxed execution policy to RemoteSigned (CurrentUser)"
)

:: --- 8. Drop a doctor helper for support -----------------------------------
set "DOCTOR=%APPDATA%\ClaudeInstaller\claude-doctor.cmd"
> "%DOCTOR%" echo @echo off
>>"%DOCTOR%" echo echo ===== claude-doctor =====
>>"%DOCTOR%" echo ver
>>"%DOCTOR%" echo echo USER=%%USERNAME%% USERPROFILE=%%USERPROFILE%%
>>"%DOCTOR%" echo echo. ^& echo --- PATH --- ^& echo %%PATH%%
>>"%DOCTOR%" echo echo. ^& echo --- node --- ^& where node ^& node -v
>>"%DOCTOR%" echo echo. ^& echo --- git ---  ^& where git ^& git --version
>>"%DOCTOR%" echo echo. ^& echo --- claude --- ^& where claude ^& claude --version
>>"%DOCTOR%" echo echo. ^& echo --- install log ---
>>"%DOCTOR%" echo type "%%APPDATA%%\ClaudeInstaller\install.log"
call :log "Doctor helper at %DOCTOR%"

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
