@echo off
setlocal EnableDelayedExpansion

:: Accessibility Audit Tool - Windows Command Prompt launcher
:: Starts the backend (FastAPI) and frontend (React) servers.
:: Matches the behavior of start.sh on Windows.
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

:: ── Locate Python 3.11 ───────────────────────────────────────────────────────

echo.
echo ^>^>^> Checking Python 3.11...

set "PY311_CMD="
set "PY311_ARG="

:: Try Windows Python Launcher (py -3.11) first
where py >nul 2>&1
if not errorlevel 1 (
    py -3.11 -c "import sys; exit(0 if sys.version_info.minor==11 else 1)" >nul 2>&1
    if not errorlevel 1 (
        set "PY311_CMD=py"
        set "PY311_ARG=-3.11"
    )
)

:: Fall back to default python command
if not defined PY311_CMD (
    where python >nul 2>&1
    if not errorlevel 1 (
        python -c "import sys; exit(0 if sys.version_info.minor==11 else 1)" >nul 2>&1
        if not errorlevel 1 set "PY311_CMD=python"
    )
)

:: If still not found, attempt winget install
if not defined PY311_CMD (
    echo   Python 3.11 not found. Attempting automatic installation...
    where winget >nul 2>&1
    if errorlevel 1 (
        echo.
        echo ERROR: winget (Windows Package Manager) was not found.
        echo   winget ships with Windows 10 1809+ / Windows 11.
        echo   Install Python 3.11 manually from https://www.python.org/downloads/
        echo   Tick "Add Python to PATH" during setup, then re-run this script.
        pause
        exit /b 1
    )
    winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
    :: Refresh PATH for this session
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
    for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USRPATH=%%B"
    set "PATH=!SYSPATH!;!USRPATH!"
    :: Re-check after install
    where py >nul 2>&1
    if not errorlevel 1 (
        py -3.11 -c "import sys; exit(0 if sys.version_info.minor==11 else 1)" >nul 2>&1
        if not errorlevel 1 (
            set "PY311_CMD=py"
            set "PY311_ARG=-3.11"
        )
    )
    if not defined PY311_CMD (
        where python >nul 2>&1
        if not errorlevel 1 (
            python -c "import sys; exit(0 if sys.version_info.minor==11 else 1)" >nul 2>&1
            if not errorlevel 1 set "PY311_CMD=python"
        )
    )
)

if not defined PY311_CMD (
    echo.
    echo ERROR: Python 3.11 not found after installation attempt.
    echo   Install Python 3.11 from https://www.python.org/downloads/
    echo   Tick "Add Python to PATH" during setup, then re-run this script.
    pause
    exit /b 1
)

if "!PY311_ARG!"=="" (
    for /f "tokens=*" %%V in ('python --version 2^>^&1') do echo   Found: %%V
) else (
    for /f "tokens=*" %%V in ('py -3.11 --version 2^>^&1') do echo   Found: %%V
)

:: ── Check / install Node.js / npm ───────────────────────────────────────────

echo.
echo ^>^>^> Checking Node.js / npm...

where npm >nul 2>&1
if errorlevel 1 (
    echo   WARNING: npm not found. Attempting automatic installation...
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

for /f "tokens=*" %%V in ('npm --version 2^>^&1') do echo   Found: npm %%V

:: ── Remove stale virtual environments ─────────────────────────────────────────

echo.
echo ^>^>^> Checking virtual environment...

for %%D in (venv env .env venv3 .venv3 .venv_old) do (
    if exist "%%D\" (
        echo   ! Removing stale environment: %%D
        rmdir /s /q "%%D"
    )
)

:: ── Virtual environment health check and creation ────────────────────────────

set "VENV_HEALTHY=0"
if exist ".venv\Scripts\python.exe" (
    .venv\Scripts\python.exe -c "import sys; exit(0 if sys.version_info.minor==11 else 1)" >nul 2>&1
    if not errorlevel 1 (
        .venv\Scripts\python.exe -c "import importlib.util,sys; missing=[p for p in ['fastapi','uvicorn','cv2','torch','reportlab'] if importlib.util.find_spec(p) is None]; sys.exit(1) if missing else None" >nul 2>&1
        if not errorlevel 1 set "VENV_HEALTHY=1"
    )
    if "!VENV_HEALTHY!"=="0" echo   ! Existing venv is unhealthy.
)

if "!VENV_HEALTHY!"=="0" (
    if exist ".venv\" (
        echo   ! Removing unhealthy venv...
        rmdir /s /q .venv
    )
    echo   Creating .venv with Python 3.11...
    if "!PY311_ARG!"=="" (
        !PY311_CMD! -m venv .venv
    ) else (
        !PY311_CMD! !PY311_ARG! -m venv .venv
    )
    if errorlevel 1 (
        echo.
        echo ERROR: Virtual environment creation failed.
        pause
        exit /b 1
    )
    echo   Venv created.
)

echo   Virtual environment ready.

:: ── Backend Python dependencies ──────────────────────────────────────────────

echo.
set "NEEDS_PIP=1"
if exist ".venv\.deps-installed" (
    powershell -NoProfile -Command "if ((Get-Item 'requirements.txt').LastWriteTime -le (Get-Item '.venv\.deps-installed').LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set "NEEDS_PIP=0"
)
if "!NEEDS_PIP!"=="1" (
    echo ^>^>^> Installing backend Python dependencies...
    echo (PyTorch is large - this may take several minutes on first install)
    .venv\Scripts\python.exe -m pip install --no-cache-dir -r requirements.txt
    if errorlevel 1 (
        echo.
        echo ERROR: pip install failed. Check requirements.txt and the error above.
        pause
        exit /b 1
    )
    copy /y nul ".venv\.deps-installed" >nul
    echo   Backend dependencies installed.
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
if "!NEEDS_NPM!"=="1" (
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
    echo   Frontend dependencies installed.
) else (
    echo ^>^>^> Frontend dependencies up to date, skipping npm install.
)

:: ── Clear occupied ports ──────────────────────────────────────────────────────

echo.
echo ^>^>^> Checking for leftover processes...

for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":3000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
echo   Ports cleared.

:: ── Start backend ─────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Starting backend  -^>  http://localhost:8000
echo (PyTorch model loading may take up to 2-3 minutes on first start)

start "Backend - Accessibility Audit Tool" cmd /k "cd /d "%~dp0backend" && set PYTHONUNBUFFERED=1 && "%~dp0.venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000"

echo   Waiting for backend...
set /a TRIES=0
:WAIT_BACKEND
set /a TRIES+=1
if !TRIES! gtr 150 (
    echo.
    echo ERROR: Backend did not start within 300 seconds.
    echo   Check the backend terminal window for the error.
    pause
    exit /b 1
)
curl -s --max-time 3 http://127.0.0.1:8000/docs >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_BACKEND
)
echo   Backend is running.

:: ── Start frontend ────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Starting frontend -^>  http://localhost:3000

start "Frontend - Accessibility Audit Tool" cmd /k "cd /d "%~dp0frontend" && set BROWSER=none && set GENERATE_SOURCEMAP=false && set NODE_OPTIONS=--max-old-space-size=512 && npm start"

echo   Waiting for frontend...
set /a TRIES=0
:WAIT_FRONTEND
set /a TRIES+=1
if !TRIES! gtr 150 (
    echo.
    echo ERROR: Frontend did not start within 300 seconds.
    echo   Check the frontend terminal window for the error.
    pause
    exit /b 1
)
curl -s --max-time 3 http://localhost:3000 >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_FRONTEND
)
echo   Frontend is running.

:: ── Open browser ──────────────────────────────────────────────────────────────

echo.
echo ^>^>^> Opening browser...
start "" "http://localhost:3000"

:: ── Done ──────────────────────────────────────────────────────────────────────

echo.
echo ============================================
echo   Accessibility Audit Tool is running
echo ============================================
echo   Backend:  http://127.0.0.1:8000
echo   Frontend: http://localhost:3000
echo.
echo   Both servers are running.
echo   To stop: close the backend and frontend terminal windows.
echo.
pause
