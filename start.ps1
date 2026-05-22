# Accessibility Audit Tool - Windows launcher
# Installs ALL required tools (Python, Node.js) and dependencies, then starts both servers.
#
# Usage — open PowerShell in the project folder and run:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1

$ErrorActionPreference = "Stop"

# ── Helper functions ───────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "" ; Write-Host ">>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    WARNING: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "" ; Write-Host "ERROR: $msg" -ForegroundColor Red }

function Refresh-Path {
    # Reload PATH from the registry so newly installed tools are found immediately.
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Install-WithWinget($packageId, $toolName) {
    Write-Step "Installing $toolName via winget..."
    winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = APPINSTALLER_ERROR_ALREADY_INSTALLED (treat as success)
        Write-Err "$toolName installation failed (winget exit code $LASTEXITCODE)."
        Write-Host "  Install $toolName manually, ensure it is on PATH, then re-run this script."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Refresh-Path
}

function Ensure-Winget {
    if (Test-Command "winget") { return }

    Write-Err "winget (Windows Package Manager) was not found."
    Write-Host ""
    Write-Host "  winget ships with Windows 10 1809+ / Windows 11."
    Write-Host "  If your machine is older, install it from:"
    Write-Host "  https://aka.ms/getwinget"
    Write-Host ""
    Write-Host "  Alternatively, install Python and Node.js manually:"
    Write-Host "    Python:  https://www.python.org/downloads/"
    Write-Host "    Node.js: https://nodejs.org/"
    Write-Host "  Then re-run this script."
    Read-Host "Press Enter to exit"
    exit 1
}

function Kill-Port($port) {
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $connections) {
        try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Wait-ForUrl($url, $maxSeconds) {
    $deadline = (Get-Date).AddSeconds($maxSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 | Out-Null
            return $true
        } catch { Start-Sleep -Seconds 2 }
    }
    return $false
}

# ── Banner ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host "  Accessibility Audit Tool - Windows Setup " -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

# Always run from this script's own folder so relative paths work.
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
Write-Host "  Project root: $Root"

# ── Sanity-check project structure ────────────────────────────────────────────

foreach ($required in @("requirements.txt", "backend\main.py", "frontend\package.json")) {
    if (!(Test-Path $required)) {
        Write-Err "Required file not found: $required"
        Write-Host "  Make sure you are running this script from the project root."
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# ── Install Python (if missing) ───────────────────────────────────────────────

Write-Step "Checking Python..."

if (!(Test-Command "python")) {
    Write-Warn "Python not found. Attempting automatic installation..."
    Ensure-Winget
    Install-WithWinget "Python.Python.3.12" "Python 3.12"
    Refresh-Path
}

if (!(Test-Command "python")) {
    Write-Err "Python still not found after installation."
    Write-Host "  Please install Python manually from https://www.python.org/downloads/"
    Write-Host "  Tick 'Add Python to PATH' during setup, then re-run this script."
    Read-Host "Press Enter to exit"
    exit 1
}

$pyVersion = python --version 2>&1
Write-OK "Found: $pyVersion"

# ── Install Node.js / npm (if missing) ────────────────────────────────────────

Write-Step "Checking Node.js / npm..."

if (!(Test-Command "npm") -and !(Test-Command "npm.cmd")) {
    Write-Warn "npm not found. Attempting automatic installation..."
    Ensure-Winget
    Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS"
    Refresh-Path
}

$npmCmd = if (Test-Command "npm.cmd") { "npm.cmd" } elseif (Test-Command "npm") { "npm" } else { $null }

if (!$npmCmd) {
    Write-Err "npm still not found after installation."
    Write-Host "  Please install Node.js manually from https://nodejs.org/"
    Read-Host "Press Enter to exit"
    exit 1
}

$npmVersion = & $npmCmd --version 2>&1
Write-OK "Found: npm $npmVersion"

# ── Python virtual environment ─────────────────────────────────────────────────

Write-Step "Setting up Python virtual environment..."

if (!(Test-Path ".venv\Scripts\python.exe")) {
    Write-Host "  Creating .venv..."
    python -m venv .venv
}

$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"
$VenvPip    = Join-Path $Root ".venv\Scripts\pip.exe"

if (!(Test-Path $VenvPython)) {
    Write-Err "Virtual environment creation failed."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-OK "Virtual environment ready."

# ── Backend Python dependencies ────────────────────────────────────────────────

$pipStamp = ".venv\.deps-installed"
if ((Test-Path $pipStamp) -and (Get-Item "requirements.txt").LastWriteTime -le (Get-Item $pipStamp).LastWriteTime) {
    Write-Step "Backend dependencies up to date, skipping pip install."
} else {
    Write-Step "Installing backend Python dependencies..."
    & $VenvPython -m pip install --upgrade pip --quiet
    & $VenvPython -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Err "pip install failed. Check requirements.txt and the error above."
        Read-Host "Press Enter to exit"
        exit 1
    }
    New-Item -Path $pipStamp -ItemType File -Force | Out-Null
    Write-OK "Backend dependencies installed."
}

# ── Frontend Node.js dependencies ─────────────────────────────────────────────

$npmStamp = "frontend\node_modules\.install-stamp"
$needsNpm = $true
if (Test-Path $npmStamp) {
    $stampTime = (Get-Item $npmStamp).LastWriteTime
    $pkgNewer  = (Get-Item "frontend\package.json").LastWriteTime -gt $stampTime
    $lockNewer = (Test-Path "frontend\package-lock.json") -and (Get-Item "frontend\package-lock.json").LastWriteTime -gt $stampTime
    if (!$pkgNewer -and !$lockNewer) { $needsNpm = $false }
}
if ($needsNpm) {
    Write-Step "Installing frontend Node.js dependencies..."
    Push-Location "frontend"
    & $npmCmd ci 2>$null
    if ($LASTEXITCODE -ne 0) { & $npmCmd install }
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Err "npm install failed. Check frontend/package.json and the error above."
        Read-Host "Press Enter to exit"
        exit 1
    }
    New-Item -Path "node_modules\.install-stamp" -ItemType File -Force | Out-Null
    Pop-Location
    Write-OK "Frontend dependencies installed."
} else {
    Write-Step "Frontend dependencies up to date, skipping npm install."
}

# ── Clear occupied ports ───────────────────────────────────────────────────────

Write-Step "Clearing ports 8000 and 3000..."
Kill-Port 8000
Kill-Port 3000
Write-OK "Ports cleared."

# ── Start backend ──────────────────────────────────────────────────────────────

Write-Step "Starting backend  ->  http://127.0.0.1:8000"
Write-Host "  (first start may take ~15 seconds while PyTorch loads)"

$BackendPath    = Join-Path $Root "backend"
$BackendCommand = "cd /d `"$BackendPath`" && `"$VenvPython`" -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload"

Start-Process cmd.exe -ArgumentList "/k", $BackendCommand -WindowStyle Normal

Write-Host "  Waiting for backend to become ready..."
if (!(Wait-ForUrl "http://127.0.0.1:8000/docs" 80)) {
    Write-Err "Backend did not start within 80 seconds."
    Write-Host "  Check the backend terminal window for the error."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-OK "Backend is running."

# ── Start frontend ─────────────────────────────────────────────────────────────

Write-Step "Starting frontend ->  http://localhost:3000"

$FrontendPath    = Join-Path $Root "frontend"
$FrontendCommand = "cd /d `"$FrontendPath`" && $npmCmd start"

Start-Process cmd.exe -ArgumentList "/k", $FrontendCommand -WindowStyle Normal

Write-Host "  Waiting for frontend to become ready..."
if (!(Wait-ForUrl "http://localhost:3000" 80)) {
    Write-Err "Frontend did not start within 80 seconds."
    Write-Host "  Check the frontend terminal window for the error."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-OK "Frontend is running."

# ── Open browser ───────────────────────────────────────────────────────────────

Write-Step "Opening app in default browser..."
Start-Process "http://localhost:3000"

# ── Done ───────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Accessibility Audit Tool is running       " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Backend:  http://127.0.0.1:8000"
Write-Host "  Frontend: http://localhost:3000"
Write-Host ""
Write-Host "  To stop: close the backend and frontend terminal windows."
Write-Host ""
Read-Host "Press Enter to close this launcher window"
