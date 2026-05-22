@echo off
setlocal EnableDelayedExpansion

:: Accessibility Audit Tool - Windows Command Prompt launcher
:: Installs ALL required tools (Python, Node.js) and dependencies, then starts both servers.
::
:: Usage - open Command Prompt in the project folder and run:
::   start.bat

title Accessibility Audit Tool - Setup

echo.
echo ============================================
echo   Accessibility Audit Tool - Windows Setup
echo ============================================

:: Always run from this script's own folder so relative paths work.
cd /d "%~dp0"
echo   Project root: %~dp0

:: ── Sanity-check project structure ──────────────────────────────────────────

if not exist "requirements.txt" (
    echo.
    echo ERROR: Required file not found: requirements.txt
    echo   Make sure you are running this script from the project root.
    pause
    exit /b 1
)
if not exist "backend\main.py" (
    echo.
    echo ERROR: Required file not found: backend\main.py
    echo   Make sure you are running this script from the project root.
    pause
    exit /b 1
)
if not exist "frontend\package.json" (
    echo.
    echo ERROR: Required file not found: frontend\package.json
    echo   Make sure you are running this script from the project root.
    pause
    exit /b 1
)

:: ── Check / install Python ───────────────────────────────────────────────────

echo.
echo ^>^>^> Checking Python...

where python >nul 2>&1
if errorlevel 1 (
    echo     WARNING: Python not found. Attempting automatic installation...
    where winget >nul 2>&1
    if errorlevel 1 (
        echo.
        echo ERROR: winget (Windows Package Manager) was not found.
        echo   winget ships with Windows 10 1809+ / Windows 11.
        echo   Install Python manually from https://www.python.org/downloads/
        echo   Tick "Add Python to PATH" during setup, then re-run this script.
        pause
        exit /b 1
    )
    winget install --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    :: Refresh PATH for this session
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
    for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USRPATH=%%B"
    set "PATH=!SYSPATH!;!USRPATH!"
)

where python >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Python still not found after installation.
    echo   Please install Python manually from https://www.python.org/downloads/
    echo   Tick "Add Python to PATH" during setup, then re-run this script.
    pause
    exit /b 1
)

for /f "tokens=*" %%V in ('python --version 2^>^&1') do echo     Found: %%V

:: ── Check / install Node.js / npm ───────────────────────────────────────────

echo.
echo ^>^>^> Checking Node.js / npm...

where npm >nul 2>&1
if errorlevel 1 (
    echo     WARNING: npm not found. Attempting automatic installation...
    where winget >nul 2>&1
    if errorlevel 1 (
        echo.
        echo ERROR: winget (Windows Package Manager) was not found.
        echo   Install Node.js manually from https://nodejs.org/
        pause
        exit /b 1
    )
    winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
    for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USRPATH=%%B"
    set "PATH=!SYSPATH!;!USRPATH!"
)

where npm >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: npm still not found after installation.
    echo   Please install Node.js manually from https://nodejs.org/
    pause
    exit /b 1
)

for /f "tokens=*" %%V in ('npm --version 2^>^&1') do echo     Found: npm %%V

:: ── Python virtual environment ───────────────────────────────────────────────

echo.
echo ^>^>^> Setting up Python virtual environment...

if not exist ".venv\Scripts\python.exe" (
    echo   Creating .venv...
    python -m venv .venv
)

if not exist ".venv\Scripts\python.exe" (
    echo.
    echo ERROR: Virtual environment creation failed.
    pause
    exit /b 1
)

echo     Virtual environment ready.

:: ── Backend Python dependencies ──────────────────────────────────────────────

echo.
set "NEEDS_PIP=1"
if exist ".venv\.deps-installed" (
    powershell -NoProfile -Command "if ((Get-Item 'requirements.txt').LastWriteTime -le (Get-Item '.venv\.deps-installed').LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set "NEEDS_PIP=0"
)
if "%NEEDS_PIP%"=="1" (
    echo ^>^>^> Installing backend Python dependencies...
    .venv\Scripts\python.exe -m pip install --upgrade pip --quiet
    .venv\Scripts\python.exe -m pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo ERROR: pip install failed. Check requirements.txt and the error above.
        pause
        exit /b 1
    )
    copy /y nul ".venv\.deps-installed" >nul
    echo     Backend dependencies installed.
) else (
    echo ^>^>^> Backend dependencies up to date, skipping pip install.
)

:: ── Frontend Node.js dependencies ────────────────────────────────────────────

echo.
set "NEEDS_NPM=1"
if exist "frontend\node_modules\.install-stamp" (
    powershell -NoProfile -Command "if ((Get-Item 'frontend/package.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime -and (!(Test-Path 'frontend/package-lock.json') -or (Get-Item 'frontend/package-lock.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime)) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set "NEEDS_NPM=0"
)
if "%NEEDS_NPM%"=="1" (
    echo ^>^>^> Installing frontend Node.js dependencies...
    pushd frontend
    npm ci 2>nul
    if errorlevel 1 npm install
    if errorlevel 1 (
        popd
        echo.
        echo ERROR: npm install failed. Check frontend/package.json and the error above.
        pause
        exit /b 1
    )
    copy /y nul "node_modules\.install-stamp" >nul
    popd
    echo     Frontend dependencies installed.
) else (
    echo ^>^>^> Frontend dependencies up to date, skipping npm install.
)

:: ── Clear occupied ports ──────────────────────────────────────────────────────

echo.
echo ^>^>^> Clearing ports 8000 and 3000...

for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":3000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
echo     Ports cleared.

:: ── Start backend ─────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Starting backend  -^>  http://127.0.0.1:8000
echo   (first start may take ~15 seconds while PyTorch loads)

start "Backend - Accessibility Audit Tool" cmd /k "cd /d "%~dp0backend" && "%~dp0.venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload"

echo   Waiting for backend to become ready...
set /a TRIES=0
:WAIT_BACKEND
set /a TRIES+=1
if !TRIES! gtr 40 (
    echo.
    echo ERROR: Backend did not start within 80 seconds.
    echo   Check the backend terminal window for the error.
    pause
    exit /b 1
)
curl -s --max-time 3 http://127.0.0.1:8000/docs >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_BACKEND
)
echo     Backend is running.

:: ── Start frontend ────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Starting frontend -^>  http://localhost:3000

start "Frontend - Accessibility Audit Tool" cmd /k "cd /d "%~dp0frontend" && npm start"

echo   Waiting for frontend to become ready...
set /a TRIES=0
:WAIT_FRONTEND
set /a TRIES+=1
if !TRIES! gtr 40 (
    echo.
    echo ERROR: Frontend did not start within 80 seconds.
    echo   Check the frontend terminal window for the error.
    pause
    exit /b 1
)
curl -s --max-time 3 http://localhost:3000 >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_FRONTEND
)
echo     Frontend is running.

:: ── Open browser ──────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Opening app in default browser...
start "" "http://localhost:3000"

:: ── Done ──────────────────────────────────────────────────────────────────────

echo.
echo ============================================
echo   Accessibility Audit Tool is running
echo ============================================
echo   Backend:  http://127.0.0.1:8000
echo   Frontend: http://localhost:3000
echo.
echo   To stop: close the backend and frontend terminal windows.
echo.
pause
