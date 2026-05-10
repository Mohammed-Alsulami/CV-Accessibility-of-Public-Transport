@echo off
setlocal

title AAT Launcher

echo ============================================
echo Starting Accessibility Audit AI on Windows
echo ============================================

cd /d "%~dp0"

echo Project root:
cd

if not exist "requirements.txt" (
    echo ERROR: requirements.txt not found.
    pause
    exit /b 1
)

if not exist "backend\main.py" (
    echo ERROR: backend\main.py not found.
    pause
    exit /b 1
)

if not exist "frontend\package.json" (
    echo ERROR: frontend\package.json not found.
    pause
    exit /b 1
)

where python >nul 2>nul
if errorlevel 1 (
    echo ERROR: Python not found. Install Python and add it to PATH.
    pause
    exit /b 1
)

where npm.cmd >nul 2>nul
if errorlevel 1 (
    echo ERROR: npm not found. Install Node.js.
    pause
    exit /b 1
)

if not exist ".venv" (
    echo Creating virtual environment...
    python -m venv .venv
)

echo.
echo Installing backend dependencies...
call ".venv\Scripts\activate.bat"
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

if errorlevel 1 (
    echo ERROR: Backend dependency installation failed.
    pause
    exit /b 1
)

echo.
echo Installing frontend dependencies...
cd /d "%~dp0frontend"
npm.cmd install

if errorlevel 1 (
    echo ERROR: Frontend dependency installation failed.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo Clearing old ports...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8000"') do taskkill /PID %%a /F >nul 2>nul
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3000"') do taskkill /PID %%a /F >nul 2>nul

echo.
echo Starting backend...
start "AAT Backend" cmd /k "cd /d ""%~dp0backend"" && call ""%~dp0.venv\Scripts\activate.bat"" && python -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload"

echo.
echo Starting frontend...
start "AAT Frontend" cmd /k "cd /d ""%~dp0frontend"" && npm.cmd start"

echo.
echo Waiting for servers to start...
timeout /t 12 /nobreak >nul

echo.
echo Opening frontend...
start "" "http://localhost:3000"

echo.
echo ============================================
echo Startup attempted.
echo Backend:  http://127.0.0.1:8000
echo Frontend: http://localhost:3000
echo ============================================
echo.
echo If the page does not load, check the opened windows:
echo - AAT Backend
echo - AAT Frontend
echo.
pause
