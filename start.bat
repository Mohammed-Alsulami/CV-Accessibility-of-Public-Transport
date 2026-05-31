@echo off
setlocal

title Accessibility Audit Tool - Windows Setup

echo.
echo ============================================
echo   Accessibility Audit Tool - Windows Setup
echo ============================================

cd /d "%~dp0"

echo   Project root: %cd%

:: ------------------------------------------------------------------
:: Check project files
:: ------------------------------------------------------------------

if not exist requirements.txt (
    echo ERROR: requirements.txt not found
    exit /b 1
)

if not exist backend\main.py (
    echo ERROR: backend\main.py not found
    exit /b 1
)

if not exist frontend\package.json (
    echo ERROR: frontend\package.json not found
    exit /b 1
)

:: ------------------------------------------------------------------
:: Python check  (py -3.11 preferred; falls back to python on PATH)
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Checking Python...

set PY_CMD=
where py >nul 2>&1
if not errorlevel 1 (
    py -3.11 --version >nul 2>&1
    if not errorlevel 1 set PY_CMD=py -3.11
)
if not defined PY_CMD (
    where python >nul 2>&1
    if not errorlevel 1 set PY_CMD=python
)
if not defined PY_CMD (
    echo ERROR: Python not found. Install Python 3.11 from https://www.python.org/
    exit /b 1
)

for /f "tokens=*" %%V in ('%PY_CMD% --version 2^>^&1') do echo   Found: %%V

:: ------------------------------------------------------------------
:: Node / npm check
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Checking Node.js / npm...

where npm >nul 2>&1
if errorlevel 1 (
    echo ERROR: npm not found. Install Node.js from https://nodejs.org/
    exit /b 1
)
for /f "tokens=*" %%V in ('npm --version 2^>^&1') do echo   Found npm %%V

:: ------------------------------------------------------------------
:: Detect Node major version for NODE_OPTIONS
:: (react-scripts / webpack may need --openssl-legacy-provider on Node 17+)
:: ------------------------------------------------------------------

set NODE_MAJOR=0
for /f "tokens=1 delims=." %%V in ('node --version 2^>nul') do set NODE_MAJOR=%%V
set NODE_MAJOR=%NODE_MAJOR:v=%
set NODE_OPTIONS=
if %NODE_MAJOR% geq 17 set NODE_OPTIONS=--openssl-legacy-provider

:: ------------------------------------------------------------------
:: Remove stale virtual environments from previous setups
:: ------------------------------------------------------------------

for %%D in (venv env .env venv3 .venv3 .venv_old) do (
    if exist "%%D\" (
        echo   Removing stale environment: %%D
        rmdir /s /q "%%D"
    )
)

:: ------------------------------------------------------------------
:: Virtual environment — reuse if healthy, else create fresh
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Checking virtual environment...

set VENV_HEALTHY=0
if exist ".venv\Scripts\python.exe" (
    .venv\Scripts\python.exe --version >nul 2>&1
    if not errorlevel 1 set VENV_HEALTHY=1
)

if "%VENV_HEALTHY%"=="0" (
    if exist ".venv" (
        echo   Removing unhealthy .venv...
        rmdir /s /q .venv
    )
    echo   Creating .venv...
    %PY_CMD% -m venv .venv
    if errorlevel 1 (
        echo ERROR: Failed to create virtual environment
        exit /b 1
    )
    echo   Virtual environment created.
) else (
    echo   Virtual environment is healthy, reusing.
)

:: ------------------------------------------------------------------
:: Backend dependencies — skip if requirements.txt hasn't changed
:: ------------------------------------------------------------------

echo.

set NEEDS_PIP=1
if exist ".venv\.deps-installed" (
    powershell -NoProfile -Command "if ((Get-Item 'requirements.txt').LastWriteTime -le (Get-Item '.venv\.deps-installed').LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set NEEDS_PIP=0
)

if "%NEEDS_PIP%"=="1" (
    echo ^>^>^> Installing backend dependencies...
    echo     ^(PyTorch is large - first install may take several minutes^)
    .venv\Scripts\python.exe -m pip install --upgrade pip --quiet
    .venv\Scripts\python.exe -m pip install --no-cache-dir -r requirements.txt
    if errorlevel 1 (
        echo ERROR: pip install failed
        exit /b 1
    )
    copy /y nul ".venv\.deps-installed" >nul
    echo   Backend dependencies installed.
) else (
    echo ^>^>^> Backend dependencies are up to date, skipping pip install.
)

:: ------------------------------------------------------------------
:: Frontend dependencies — skip if package.json / lock haven't changed
:: ------------------------------------------------------------------

echo.

set NEEDS_NPM=1
if exist "frontend\node_modules\.install-stamp" (
    powershell -NoProfile -Command "if ((Get-Item 'frontend/package.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime -and (!(Test-Path 'frontend/package-lock.json') -or (Get-Item 'frontend/package-lock.json').LastWriteTime -le (Get-Item 'frontend/node_modules/.install-stamp').LastWriteTime)) { exit 0 } else { exit 1 }" >nul 2>&1
    if not errorlevel 1 set NEEDS_NPM=0
)

if "%NEEDS_NPM%"=="1" (
    echo ^>^>^> Installing frontend dependencies...
    cd frontend
    call npm ci 2>nul
    if errorlevel 1 call npm install
    if errorlevel 1 (
        cd ..
        echo ERROR: npm install failed
        exit /b 1
    )
    copy /y nul "node_modules\.install-stamp" >nul
    cd ..
    echo   Frontend dependencies installed.
) else (
    echo ^>^>^> Frontend dependencies are up to date, skipping npm install.
)

:: ------------------------------------------------------------------
:: Clear occupied ports
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Checking for leftover processes...

for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":8000 " ^| findstr "LISTENING"') do taskkill /PID %%P /F >nul 2>&1
for /f "tokens=5" %%P in ('netstat -ano 2^>nul ^| findstr ":3000 " ^| findstr "LISTENING"') do taskkill /PID %%P /F >nul 2>&1
echo   Ports cleared.

:: ------------------------------------------------------------------
:: Start backend
:: (CI: background /B, no window; Local: named /k window stays open)
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Starting backend  -^>  http://127.0.0.1:8000
echo     ^(PyTorch model loading may take 2-3 min on first start^)

if defined GITHUB_ACTIONS (
    start "" /B cmd /c "cd backend && set PYTHONUNBUFFERED=1 && ..\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000"
) else (
    start "Backend - Accessibility Audit Tool" cmd /k "cd backend && set PYTHONUNBUFFERED=1 && ..\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000"
)

:: ------------------------------------------------------------------
:: Start frontend
:: (CI: background /B, no window; Local: named /k window stays open)
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Starting frontend -^>  http://localhost:3000

if defined GITHUB_ACTIONS (
    start "" /B cmd /c "cd frontend && set BROWSER=none && set GENERATE_SOURCEMAP=false && npm start"
) else (
    start "Frontend - Accessibility Audit Tool" cmd /k "cd frontend && set BROWSER=none && set GENERATE_SOURCEMAP=false && npm start"
)

:: ------------------------------------------------------------------
:: Poll for backend  (60 x 5 s = 5 min max)
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Waiting for backend (up to 5 min)...

set TRIES=0
:WAIT_BACKEND
set /a TRIES=TRIES+1
if %TRIES% gtr 60 (
    echo ERROR: Backend did not respond after 5 minutes
    exit /b 1
)
curl -s --max-time 3 http://127.0.0.1:8000/docs >nul 2>&1
if errorlevel 1 (
    timeout /t 5 /nobreak >nul
    goto WAIT_BACKEND
)
echo   Backend is running.

:: ------------------------------------------------------------------
:: Poll for frontend  (60 x 5 s = 5 min max)
:: ------------------------------------------------------------------

echo.
echo ^>^>^> Waiting for frontend (up to 5 min)...

set TRIES=0
:WAIT_FRONTEND
set /a TRIES=TRIES+1
if %TRIES% gtr 60 (
    echo ERROR: Frontend did not respond after 5 minutes
    exit /b 1
)
curl -s --max-time 3 http://localhost:3000 >nul 2>&1
if errorlevel 1 (
    timeout /t 5 /nobreak >nul
    goto WAIT_FRONTEND
)
echo   Frontend is running.

:: ------------------------------------------------------------------
:: Done
:: ------------------------------------------------------------------

echo.
echo ============================================
echo   Accessibility Audit Tool is running
echo ============================================
echo   Backend:  http://127.0.0.1:8000
echo   Frontend: http://localhost:3000
echo.
echo   Both servers are running.
echo   To stop: close the backend and frontend terminal windows.

if defined GITHUB_ACTIONS exit /b 0

echo.
echo ^>^>^> Opening browser...
start "" "http://localhost:3000"
pause
