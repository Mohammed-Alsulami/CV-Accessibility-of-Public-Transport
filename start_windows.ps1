# Accessibility Audit Tool Windows start script
# Usage:
#   .\start_windows.bat
# or:
#   powershell -ExecutionPolicy Bypass -File .\start_windows.ps1

$ErrorActionPreference = "Stop"

Write-Host "============================================"
Write-Host "Starting Accessibility Audit Tool on Windows"
Write-Host "============================================"

# Always run from this script's folder
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host ""
Write-Host "Project root:"
Write-Host $Root

# Check required files and folders
if (!(Test-Path "requirements.txt")) {
    Write-Host "ERROR: requirements.txt not found"
    Write-Host "Place start_windows.bat and start_windows.ps1 in the project root"
    Read-Host "Press Enter to exit"
    exit 1
}

if (!(Test-Path "backend\main.py")) {
    Write-Host "ERROR: backend\main.py not found"
    Read-Host "Press Enter to exit"
    exit 1
}

if (!(Test-Path "frontend\package.json")) {
    Write-Host "ERROR: frontend\package.json not found"
    Read-Host "Press Enter to exit"
    exit 1
}

# Check Python
if (!(Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Python was not found"
    Write-Host "Install Python and tick Add Python to PATH"
    Read-Host "Press Enter to exit"
    exit 1
}

# Check npm
if (!(Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: npm was not found"
    Write-Host "Install Node.js first"
    Read-Host "Press Enter to exit"
    exit 1
}

# Create virtual environment if missing
if (!(Test-Path ".venv\Scripts\python.exe")) {
    Write-Host ""
    Write-Host "Creating Python virtual environment..."
    python -m venv .venv
}

$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"

# Install backend dependencies
Write-Host ""
Write-Host "Installing backend Python dependencies..."
& $VenvPython -m pip install --upgrade pip
& $VenvPython -m pip install -r requirements.txt

# Install frontend dependencies
Write-Host ""
Write-Host "Installing frontend Node.js dependencies..."
Push-Location "frontend"
npm.cmd install
Pop-Location

# Clear ports 8000 and 3000 if in use
Write-Host ""
Write-Host "Clearing ports 8000 and 3000 if already in use..."

foreach ($port in @(8000, 3000)) {
    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue

    foreach ($connection in $connections) {
        try {
            Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
        } catch {
            # Ignore if process cannot be stopped
        }
    }
}

# Start backend
Write-Host ""
Write-Host "Starting backend on http://127.0.0.1:8000"

$BackendPath = Join-Path $Root "backend"
$BackendCommand = "cd /d `"$BackendPath`" && `"$VenvPython`" -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload"

Start-Process cmd.exe -ArgumentList "/k", $BackendCommand -WindowStyle Normal

# Wait for backend
Write-Host "Waiting for backend to start..."

$backendReady = $false

for ($i = 1; $i -le 40; $i++) {
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:8000/docs" -UseBasicParsing -TimeoutSec 2 | Out-Null
        $backendReady = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (!$backendReady) {
    Write-Host ""
    Write-Host "ERROR: Backend did not start"
    Write-Host "Check the opened backend terminal window for the exact error"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Backend is running"

# Start frontend
Write-Host ""
Write-Host "Starting frontend on http://localhost:3000"

$FrontendPath = Join-Path $Root "frontend"
$FrontendCommand = "cd /d `"$FrontendPath`" && npm.cmd start"

Start-Process cmd.exe -ArgumentList "/k", $FrontendCommand -WindowStyle Normal

# Wait for frontend
Write-Host "Waiting for frontend to start..."

$frontendReady = $false

for ($i = 1; $i -le 40; $i++) {
    try {
        Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 2 | Out-Null
        $frontendReady = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (!$frontendReady) {
    Write-Host ""
    Write-Host "ERROR: Frontend did not start"
    Write-Host "Check the opened frontend terminal window for the exact error"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Frontend is running"

# Open browser
Write-Host ""
Write-Host "Opening app in browser..."
Start-Process "http://localhost:3000"

Write-Host ""
Write-Host "============================================"
Write-Host "Accessibility Audit Tool is running"
Write-Host "Backend:  http://127.0.0.1:8000"
Write-Host "Frontend: http://localhost:3000"
Write-Host "============================================"
Write-Host ""
Write-Host "To stop the app, close the backend and frontend terminal windows"
Write-Host ""

Read-Host "Press Enter to close this launcher window"
