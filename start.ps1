# Accessibility Audit Tool - Windows PowerShell launcher
# Starts the backend (FastAPI) and frontend (React) servers.
# Matches the behavior of start.sh on Windows.
#
# Usage — open PowerShell in the project folder and run:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1

$ErrorActionPreference = "Stop"
$REQUIRED_PYTHON_MINOR = 11
$VENV_DIR = ".venv"

# ── Helper functions ───────────────────────────────────────────────────────────

function Write-Info($msg) { Write-Host "  $msg" }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host ""; Write-Host ">>> $msg" -ForegroundColor Cyan }
function Write-Err($msg)  { Write-Host ""; Write-Host "ERROR: $msg" -ForegroundColor Red }

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Install-WithWinget($packageId, $toolName) {
    if (!(Test-Command "winget")) {
        Write-Err "winget (Windows Package Manager) was not found."
        Write-Host "  winget ships with Windows 10 1809+ / Windows 11."
        Write-Host "  Install $toolName manually, ensure it is on PATH, then re-run this script."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Info "Installing $toolName via winget..."
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

function Find-Python311 {
    # Windows Python Launcher (py) can select specific installed versions
    if (Test-Command "py") {
        $minor = py -3.11 -c "import sys; print(sys.version_info.minor)" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$minor".Trim() -eq "$REQUIRED_PYTHON_MINOR") {
            $exePath = py -3.11 -c "import sys; print(sys.executable)" 2>$null
            if ($exePath) { return $exePath.Trim() }
        }
    }
    foreach ($candidate in @("python3.11", "python3", "python")) {
        if (!(Test-Command $candidate)) { continue }
        $minor = & $candidate -c "import sys; print(sys.version_info.minor)" 2>$null
        if ($LASTEXITCODE -eq 0 -and "$minor".Trim() -eq "$REQUIRED_PYTHON_MINOR") {
            return (Get-Command $candidate).Source
        }
    }
    return $null
}

function Test-VenvOk {
    $venvPy = Join-Path $VENV_DIR "Scripts\python.exe"
    if (!(Test-Path "$VENV_DIR\Scripts\Activate.ps1")) { Write-Warn "venv missing activate script."; return $false }
    if (!(Test-Path $venvPy))                          { Write-Warn "venv missing python binary.";   return $false }

    $minor = & $venvPy -c "import sys; print(sys.version_info.minor)" 2>$null
    if ("$minor".Trim() -ne "$REQUIRED_PYTHON_MINOR") {
        Write-Warn "venv python is 3.$minor, need 3.$REQUIRED_PYTHON_MINOR."
        return $false
    }

    & $venvPy -c "import importlib.util, sys; missing=[p for p in ['fastapi','uvicorn','cv2','torch','reportlab'] if importlib.util.find_spec(p) is None]; sys.exit(1) if missing else None" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "venv is missing required packages."
        return $false
    }
    return $true
}

function Remove-StaleVenvs {
    foreach ($dir in @("venv", "env", ".env", "venv3", ".venv3", ".venv_old")) {
        if (Test-Path $dir) {
            Write-Warn "Removing stale environment: $dir"
            Remove-Item -Recurse -Force $dir
        }
    }
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

# ── Virtual environment setup ─────────────────────────────────────────────────

Write-Step "Checking virtual environment..."
Remove-StaleVenvs

if (!(Test-VenvOk)) {
    if (Test-Path $VENV_DIR) {
        Write-Warn "Existing venv is unhealthy — removing it."
        Remove-Item -Recurse -Force $VENV_DIR
    }

    $Python311 = Find-Python311
    if (!$Python311) {
        Write-Info "Python 3.11 not found. Attempting automatic installation..."
        Install-WithWinget "Python.Python.3.11" "Python 3.11"
        $Python311 = Find-Python311
    }
    if (!$Python311) {
        Write-Err "Python 3.11 not found after installation attempt."
        Write-Host "  Install Python 3.11 from https://www.python.org/downloads/"
        Write-Host "  Tick 'Add Python to PATH' during setup, then re-run this script."
        Read-Host "Press Enter to exit"
        exit 1
    }

    $pyVersion = & $Python311 --version 2>&1
    Write-Info "Creating new venv with $Python311 ($pyVersion)..."
    & $Python311 -m venv $VENV_DIR
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to create virtual environment."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Info "Venv created."
}

Write-Info "Virtual environment ready."

$VenvPython = Join-Path $Root "$VENV_DIR\Scripts\python.exe"

# ── Check / install Node.js / npm ─────────────────────────────────────────────

Write-Step "Checking Node.js / npm..."

if (!(Test-Command "npm") -and !(Test-Command "npm.cmd")) {
    Write-Warn "npm not found. Attempting automatic installation..."
    Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS"
}

$npmCmd = if (Test-Command "npm.cmd") { "npm.cmd" } elseif (Test-Command "npm") { "npm" } else { $null }

if (!$npmCmd) {
    Write-Err "npm still not found after installation."
    Write-Host "  Please install Node.js manually from https://nodejs.org/"
    Read-Host "Press Enter to exit"
    exit 1
}

$npmVersion = & $npmCmd --version 2>&1
Write-Info "Found: npm $npmVersion"

# ── Backend Python dependencies ────────────────────────────────────────────────

Write-Step "Checking backend dependencies..."

$pipStamp = "$VENV_DIR\.deps-installed"
$needsPip = $true
if ((Test-Path $pipStamp) -and (Get-Item "requirements.txt").LastWriteTime -le (Get-Item $pipStamp).LastWriteTime) {
    $needsPip = $false
}

if ($needsPip) {
    Write-Info "Installing backend Python dependencies..."
    Write-Host "  (PyTorch is large — this may take several minutes on first install)"
    & $VenvPython -m pip install --no-cache-dir -r requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Err "pip install failed. Check requirements.txt and the error above."
        Read-Host "Press Enter to exit"
        exit 1
    }
    New-Item -Path $pipStamp -ItemType File -Force | Out-Null
    Write-Info "Backend dependencies installed."
} else {
    Write-Info "Backend dependencies up to date."
}

# ── Frontend Node.js dependencies ─────────────────────────────────────────────

Write-Step "Checking frontend dependencies..."

$npmStamp = "frontend\node_modules\.install-stamp"
$needsNpm = $true
if (Test-Path $npmStamp) {
    $stampTime = (Get-Item $npmStamp).LastWriteTime
    $pkgNewer  = (Get-Item "frontend\package.json").LastWriteTime -gt $stampTime
    $lockNewer = (Test-Path "frontend\package-lock.json") -and (Get-Item "frontend\package-lock.json").LastWriteTime -gt $stampTime
    if (!$pkgNewer -and !$lockNewer) { $needsNpm = $false }
}
if ($needsNpm) {
    Write-Info "Installing frontend Node.js dependencies..."
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
    Write-Info "Frontend dependencies installed."
} else {
    Write-Info "Frontend dependencies up to date."
}

# ── Clear occupied ports ───────────────────────────────────────────────────────

Write-Step "Checking for leftover processes..."
Kill-Port 8000
Kill-Port 3000
Write-Info "Ports cleared."

# ── Start backend ──────────────────────────────────────────────────────────────

Write-Step "Starting backend  ->  http://localhost:8000"
Write-Host "  (PyTorch model loading may take up to 2-3 minutes on first start)"

$BackendPath    = Join-Path $Root "backend"
$BackendCommand = "cd /d `"$BackendPath`" && set PYTHONUNBUFFERED=1 && `"$VenvPython`" -m uvicorn main:app --host 127.0.0.1 --port 8000"

Start-Process cmd.exe -ArgumentList "/k", $BackendCommand -WindowStyle Normal

Write-Info "Waiting for backend..."
if (!(Wait-ForUrl "http://127.0.0.1:8000/docs" 300)) {
    Write-Err "Backend did not start within 300 seconds."
    Write-Host "  Check the backend terminal window for the error."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Info "Backend ready!"

# ── Start frontend ─────────────────────────────────────────────────────────────

Write-Step "Starting frontend ->  http://localhost:3000"

$FrontendPath    = Join-Path $Root "frontend"
$FrontendCommand = "cd /d `"$FrontendPath`" && set BROWSER=none && set GENERATE_SOURCEMAP=false && set NODE_OPTIONS=--max-old-space-size=512 && $npmCmd start"

Start-Process cmd.exe -ArgumentList "/k", $FrontendCommand -WindowStyle Normal

Write-Info "Waiting for frontend..."
if (!(Wait-ForUrl "http://localhost:3000" 300)) {
    Write-Err "Frontend did not start within 300 seconds."
    Write-Host "  Check the frontend terminal window for the error."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Info "Frontend ready!"

# ── Open browser ───────────────────────────────────────────────────────────────

Write-Step "Opening browser..."
Start-Process "http://localhost:3000"

# ── Done ───────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Accessibility Audit Tool is running       " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Backend:  http://127.0.0.1:8000"
Write-Host "  Frontend: http://localhost:3000"
Write-Host ""
Write-Host "  Both servers are running."
Write-Host "  To stop: close the backend and frontend terminal windows."
Write-Host ""
Read-Host "Press Enter to close this launcher window"
