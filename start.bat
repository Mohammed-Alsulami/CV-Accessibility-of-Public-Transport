@echo off
setlocal

title Accessibility Audit Tool - Windows Setup

echo.
echo ============================================
echo   Accessibility Audit Tool - Windows Setup
echo ============================================

:: Go to script directory
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
:: Python check
:: ------------------------------------------------------------------

echo.
echo >>> Checking Python...

where py >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python launcher not found
    exit /b 1
)

py -3.11 --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Python 3.11 not installed
    exit /b 1
)

for /f "tokens=*" %%V in ('py -3.11 --version 2^>^&1') do (
    echo   Found: %%V
)

:: ------------------------------------------------------------------
:: Node/npm check
:: ------------------------------------------------------------------

echo.
echo >>> Checking Node.js...

where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: npm not found
    exit /b 1
)

for /f "tokens=*" %%V in ('npm --version') do (
    echo   Found npm %%V
)

:: ------------------------------------------------------------------
:: Create venv
:: ------------------------------------------------------------------

echo.
echo >>> Preparing virtual environment...

if exist .venv (
    rmdir /s /q .venv
)

py -3.11 -m venv .venv

if %errorlevel% neq 0 (
    echo ERROR: Failed creating venv
    exit /b 1
)

echo   Venv created

:: ------------------------------------------------------------------
:: Install backend deps
:: ------------------------------------------------------------------

echo.
echo >>> Installing backend dependencies...

.venv\Scripts\python.exe -m pip install --upgrade pip

.venv\Scripts\python.exe -m pip install --no-cache-dir -r requirements.txt

if %errorlevel% neq 0 (
    echo ERROR: pip install failed
    exit /b 1
)

:: ------------------------------------------------------------------
:: Install frontend deps
:: ------------------------------------------------------------------

echo.
echo >>> Installing frontend dependencies...

cd frontend

call npm install

if %errorlevel% neq 0 (
    echo ERROR: npm install failed
    exit /b 1
)

cd ..

:: ------------------------------------------------------------------
:: Kill old ports
:: ------------------------------------------------------------------

echo.
echo >>> Clearing ports...

for /f "tokens=5" %%P in ('netstat -ano ^| findstr :8000 ^| findstr LISTENING') do (
    taskkill /F /PID %%P >nul 2>&1
)

for /f "tokens=5" %%P in ('netstat -ano ^| findstr :3000 ^| findstr LISTENING') do (
    taskkill /F /PID %%P >nul 2>&1
)

:: ------------------------------------------------------------------
:: Start backend
:: ------------------------------------------------------------------

echo.
echo >>> Starting backend...

start "" /B cmd /c "cd backend && ..\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000"

timeout /t 20 /nobreak >nul

:: ------------------------------------------------------------------
:: Start frontend
:: ------------------------------------------------------------------

echo.
echo >>> Starting frontend...

start "" /B cmd /c "cd frontend && set BROWSER=none && set GENERATE_SOURCEMAP=false && npm start"

timeout /t 40 /nobreak >nul

:: ------------------------------------------------------------------
:: Verify backend
:: ------------------------------------------------------------------

powershell -Command "try { Invoke-WebRequest http://127.0.0.1:8000/docs -UseBasicParsing -TimeoutSec 5 | Out-Null; exit 0 } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo ERROR: Backend failed to start
    exit /b 1
)

:: ------------------------------------------------------------------
:: Verify frontend
:: ------------------------------------------------------------------

powershell -Command "try { Invoke-WebRequest http://localhost:3000 -UseBasicParsing -TimeoutSec 5 | Out-Null; exit 0 } catch { exit 1 }"

if %errorlevel% neq 0 (
    echo ERROR: Frontend failed to start
    exit /b 1
)

echo.
echo ============================================
echo   Accessibility Audit Tool is running
echo ============================================

echo Backend:  http://127.0.0.1:8000
echo Frontend: http://localhost:3000

if defined GITHUB_ACTIONS exit /b 0

pause