@echo off
:: Removes @anthropic-ai/claude-code globally. Called from the [UninstallRun]
:: section of installer.iss when the user removes the app from Settings → Apps.
:: Does NOT touch Node.js or Git — those were optional bundled deps and the
:: user may rely on them for other work.

set "PATH=%ProgramFiles%\nodejs;%ProgramFiles%\Git\cmd;%PATH%"

where npm >nul 2>&1
if errorlevel 1 goto :eof
call npm uninstall -g @anthropic-ai/claude-code >nul 2>&1

:: If we set a safe-path prefix at install time for Korean usernames, also
:: clean that up. Best-effort — we don't fail uninstall over leftover files.
if exist "C:\Users\Public\claude-code" rmdir /S /Q "C:\Users\Public\claude-code" 2>nul
exit /b 0
