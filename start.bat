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

:: -- Sanity-check project structure ------------------------------------------

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

:: -- Locate Python 3.11 -------------------------------------------------------

echo.
echo ^>^>^> Checking Python 3.11...

set "PY311_CMD="
set "PY311_ARG="

:: Try py launcher first
where py >nul 2>&1
if not errorlevel 1 (
    py -3.11 --version >nul 2>&1
    if not errorlevel 1 (
        set "PY311_CMD=py"
        set "PY311_ARG=-3.11"
    )
)

:: Fallback to plain python
if not defined PY311_CMD (
    where python >nul 2>&1
    if not errorlevel 1 (
        python --version >nul 2>&1
        if not errorlevel 1 (
            for /f "tokens=2 delims= " %%V in ('python --version 2^>^&1') do (
                set "PYVER=%%V"
            )

            echo !PYVER! | findstr /b "3.11" >nul
            if not errorlevel 1 (
                set "PY311_CMD=python"
            )
        )
    )
)

:: Install if missing
if not defined PY311_CMD (
    echo   Python 3.11 not found. Attempting automatic installation...

    where winget >nul 2>&1
    if errorlevel 1 (
        echo.
        echo ERROR: winget not found.
        echo Install Python 3.11 manually:
        echo https://www.python.org/downloads/
        pause
        exit /b 1
    )

    winget install --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements

    :: refresh PATH
    for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYSPATH=%%B"
    for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USRPATH=%%B"

    set "PATH=!SYSPATH!;!USRPATH!"

    where py >nul 2>&1
    if not errorlevel 1 (
        py -3.11 --version >nul 2>&1
        if not errorlevel 1 (
            set "PY311_CMD=py"
            set "PY311_ARG=-3.11"
        )
    )

    if not defined PY311_CMD (
        echo.
        echo ERROR: Python 3.11 installation failed.
        pause
        exit /b 1
    )
)

:py_have
if "!PY311_ARG!"=="" (
    for /f "tokens=*" %%V in ('python --version 2^>^&1') do echo   Found: %%V
) else (
    for /f "tokens=*" %%V in ('py -3.11 --version 2^>^&1') do echo   Found: %%V
)

:: -- Check / install Node.js / npm -------------------------------------------

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

:: -- Remove stale virtual environments ----------------------------------------

echo.
echo ^>^>^> Checking virtual environment...

for %%D in (venv env .env venv3 .venv3 .venv_old) do (
    if exist "%%D\" (
        echo   ! Removing stale environment: %%D
        rmdir /s /q "%%D"
    )
)

:: -- Virtual environment health check -----------------------------------------
:: Same parens rule as above: the importlib probe contains "(" / ")", so it is
:: run at top level (between labels), never inside an if(...) block.

set "VENV_HEALTHY=0"
if not exist ".venv\Scripts\python.exe" goto :venv_checked
.venv\Scripts\python.exe -c "import sys;assert sys.version_info.minor==11" >nul 2>&1 || goto :venv_unhealthy
.venv\Scripts\python.exe -c "import importlib.util,sys;missing=[p for p in ['fastapi','uvicorn','cv2','torch','reportlab'] if importlib.util.find_spec(p) is None];sys.exit(1 if missing else 0)" >nul 2>&1 || goto :venv_unhealthy
set "VENV_HEALTHY=1"
goto :venv_checked
:venv_unhealthy
echo   ! Existing venv is unhealthy.
:venv_checked

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

:: -- Backend Python dependencies ----------------------------------------------
:: The PowerShell freshness probe contains "(" / ")", so it runs at top level
:: with && setting the flag, never inside an if(...) block.

echo.
set "NEEDS_PIP=1"
if not exist ".venv\.deps-installed" goto :pip_decided
powershell -NoProfile -Command "if ((Get-Item 'requirements.txt').LastWriteTime -le (Get-Item '.venv\.deps-installed').LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1 && set "NEEDS_PIP=0"
:pip_decided

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

:: -- Frontend Node.js dependencies --------------------------------------------

echo.
set "NEEDS_NPM=1"
if not exist "frontend\node_modules\.install-stamp" goto :npm_decided
powershell -NoProfile -Command "if ((Get-Item 'frontend/package.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime -and (!(Test-Path 'frontend/package-lock.json') -or (Get-Item 'frontend/package-lock.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime)) { exit 0 } else { exit 1 }" >nul 2>&1 && set "NEEDS_NPM=0"
:npm_decided

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

:: -- Clear occupied ports -----------------------------------------------------

echo.
echo ^>^>^> Checking for leftover processes...

for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":3000 " ^| findstr "LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)
echo   Ports cleared.

:: -- Start backend ------------------------------------------------------------

echo.
echo ^>^>^> Starting backend  -^>  http://localhost:8000
echo (PyTorch model loading may take up to 2-3 minutes on first start)

start /B cmd /c ^
"cd /d ""%~dp0backend"" ^
&& set PYTHONUNBUFFERED=1 ^
&& ""%~dp0.venv\Scripts\python.exe"" -m uvicorn main:app --host 127.0.0.1 --port 8000"

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
powershell -Command "(Invoke-WebRequest http://127.0.0.1:8000/docs -UseBasicParsing -TimeoutSec 3) > $null" >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_BACKEND
)
echo   Backend is running.

:: -- Start frontend -----------------------------------------------------------

echo.
echo ^>^>^> Starting frontend -^>  http://localhost:3000

:: react-scripts 5 (CRA/webpack) needs OpenSSL's legacy provider on Node 17+, else
:: webpack hashing throws ERR_OSSL_EVP_UNSUPPORTED. NODE_OPTIONS is set here in the
:: parent environment so the frontend window inherits it; no fixed heap cap.
:: Node major is read via `node -v` (parens-free) to stay clear of the cmd bug.
set "NODE_MAJOR=0"

for /f %%V in ('node -p "process.versions.node.split('.')[0]"') do (
    set "NODE_MAJOR=%%V"
)

set "NODE_OPTIONS="

if !NODE_MAJOR! GEQ 17 (
    set "NODE_OPTIONS=--openssl-legacy-provider"
)

start /B cmd /c ^
"cd /d ""%~dp0frontend"" ^
&& set BROWSER=none ^
&& set CI=true ^
&& set GENERATE_SOURCEMAP=false ^
&& npm start"

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
powershell -Command "(Invoke-WebRequest http://localhost:3000 -UseBasicParsing -TimeoutSec 3) > $null" >nul 2>&1
if errorlevel 1 (
    timeout /t 2 /nobreak >nul
    goto WAIT_FRONTEND
)
echo   Frontend is running.

:: -- Open browser -------------------------------------------------------------

echo.
echo ^>^>^> Opening browser...
if not defined GITHUB_ACTIONS start "" "http://localhost:3000"

:: -- Done ---------------------------------------------------------------------

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

if defined GITHUB_ACTIONS exit /b 0
pause