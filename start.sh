#!/bin/bash
# Starts the backend (FastAPI) and frontend (React) servers.
# Usage: bash start.sh

REQUIRED_PYTHON_MINOR=11
VENV_DIR=".venv"

# ── Helpers ────────────────────────────────────────────────
_info() { echo "  $*"; }
_warn() { echo "  ! $*"; }
_die()  { echo ""; echo "ERROR: $*" >&2; exit 1; }

# ── Locate Python 3.11 ────────────────────────────────────
_find_python311() {
    for candidate in python3.11 /opt/homebrew/bin/python3.11 python3 python; do
        local cmd
        cmd=$(command -v "$candidate" 2>/dev/null) || continue
        local minor
        minor=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null) || continue
        if [ "$minor" = "$REQUIRED_PYTHON_MINOR" ]; then
            echo "$cmd"
            return 0
        fi
    done
    return 1
}

# ── Venv health check ──────────────────────────────────────
# Checks: activate exists, python binary present and is 3.11,
# and all critical packages are importable.
_venv_ok() {
    [ -f "$VENV_DIR/bin/activate" ]   || { _warn "venv missing activate script.";       return 1; }
    [ -x "$VENV_DIR/bin/python" ]     || { _warn "venv missing python binary.";          return 1; }

    local minor
    minor=$("$VENV_DIR/bin/python" -c "import sys; print(sys.version_info.minor)" 2>/dev/null) \
        || { _warn "venv python is broken."; return 1; }
    [ "$minor" = "$REQUIRED_PYTHON_MINOR" ] \
        || { _warn "venv python is 3.${minor}, need 3.${REQUIRED_PYTHON_MINOR}."; return 1; }

    "$VENV_DIR/bin/python" - <<'PYCHECK' 2>/dev/null
import importlib.util, sys
missing = [p for p in ["fastapi","uvicorn","cv2","torch","reportlab"]
           if importlib.util.find_spec(p) is None]
if missing:
    print("  ! missing packages: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PYCHECK
}

# ── Remove stale / extra venv directories ─────────────────
_clean_stale_venvs() {
    for dir in venv env .env venv3 .venv3 .venv_old; do
        if [ -d "$dir" ]; then
            _warn "Removing stale environment: $dir ($(du -sh "$dir" 2>/dev/null | cut -f1))"
            rm -rf "$dir"
        fi
    done
}

# ── Virtual environment setup ─────────────────────────────
echo ""
echo "Checking virtual environment..."
_clean_stale_venvs

if ! _venv_ok; then
    if [ -d "$VENV_DIR" ]; then
        _warn "Existing venv is unhealthy — removing it ($(du -sh "$VENV_DIR" 2>/dev/null | cut -f1))."
        rm -rf "$VENV_DIR"
    fi

    PYTHON=$(_find_python311) || _die "Python 3.11 not found. Install it with: brew install python@3.11"
    _info "Creating new venv with $PYTHON ($("$PYTHON" --version))..."
    "$PYTHON" -m venv "$VENV_DIR" || _die "Failed to create virtual environment."
    _info "Venv created."
fi

_info "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# ── Backend Python dependencies ────────────────────────────
echo ""
echo "Checking backend dependencies..."

NEED_INSTALL=0
python - <<'PYCHECK' 2>/dev/null || NEED_INSTALL=1
import importlib.util, sys
missing = [p for p in ["fastapi","uvicorn","cv2","torch","reportlab"]
           if importlib.util.find_spec(p) is None]
if missing: sys.exit(1)
PYCHECK

if [ "$NEED_INSTALL" -eq 1 ] || [ requirements.txt -nt "$VENV_DIR/.deps-installed" ]; then
    echo ""
    echo "Installing backend Python dependencies..."
    echo "(PyTorch is large — this may take several minutes on first install)"
    pip install --no-cache-dir -r requirements.txt || _die "pip install failed."
    touch "$VENV_DIR/.deps-installed"
    _info "Done. Venv size: $(du -sh "$VENV_DIR" 2>/dev/null | cut -f1)"
else
    _info "Backend dependencies up to date."
fi

# ── Frontend Node.js dependencies ─────────────────────────
echo ""
echo "Checking frontend dependencies..."

if [ ! -d frontend/node_modules ] || \
   [ frontend/package.json -nt frontend/node_modules/.install-stamp ] || \
   { [ -f frontend/package-lock.json ] && [ frontend/package-lock.json -nt frontend/node_modules/.install-stamp ]; }; then
    echo "Installing frontend Node.js dependencies..."
    (cd frontend && npm ci 2>/dev/null || npm install) && touch frontend/node_modules/.install-stamp
else
    _info "Frontend dependencies up to date."
fi

# ── Kill any leftover server processes from previous sessions ──
echo ""
echo "Checking for leftover processes..."
pkill -f "uvicorn main:app"   2>/dev/null || true
pkill -f "react-scripts start" 2>/dev/null || true

for port in 8000 3000; do
    pids=$(lsof -ti :"$port" 2>/dev/null)
    if [ -n "$pids" ]; then
        _info "Freeing port $port (pid: $pids)..."
        echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
done

# ── Start backend and frontend in parallel ─────────────────
echo ""
echo "Starting backend  →  http://localhost:8000"
echo "(PyTorch model loading may take up to 2-3 minutes on first start)"

BACKEND_LOG="$(pwd)/$VENV_DIR/backend_run.log"
(cd backend && PYTHONUNBUFFERED=1 python -m uvicorn main:app --host 127.0.0.1 --port 8000 2>&1 | tee "$BACKEND_LOG") &
BACKEND_PID=$!

echo "Starting frontend →  http://localhost:3000"

FRONTEND_LOG="$(pwd)/$VENV_DIR/frontend_run.log"
# react-scripts 5 (CRA/webpack) needs OpenSSL's legacy provider on Node 17+,
# otherwise webpack hashing throws ERR_OSSL_EVP_UNSUPPORTED. Add the flag only when
# the active Node is new enough to accept it (older Node would reject the flag).
NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)
FRONTEND_NODE_OPTIONS=""
if [ "$NODE_MAJOR" -ge 17 ]; then
    FRONTEND_NODE_OPTIONS="--openssl-legacy-provider"
fi
# GENERATE_SOURCEMAP=false skips source-map generation (big memory + startup win in dev).
# No --max-old-space-size cap: modern Node sizes its heap from the machine's RAM.
(cd frontend && env BROWSER=none GENERATE_SOURCEMAP=false NODE_OPTIONS="$FRONTEND_NODE_OPTIONS" npm start 2>&1 | tee "$FRONTEND_LOG") &
FRONTEND_PID=$!

echo -n "  Waiting for backend and frontend"
BACKEND_READY=0
FRONTEND_READY=0
for i in $(seq 1 300); do
    sleep 1

    if [ "$BACKEND_READY" -eq 0 ] && curl -sf http://127.0.0.1:8000/ > /dev/null 2>&1; then
        BACKEND_READY=1
        echo ""
        _info "Backend ready! (${i}s)"
    fi

    if [ "$FRONTEND_READY" -eq 0 ]; then
        if grep -q "Compiled successfully\|webpack compiled successfully\|webpack compiled with" "$FRONTEND_LOG" 2>/dev/null; then
            FRONTEND_READY=1
            echo ""
            _info "Frontend ready! (${i}s)"
        elif curl -sf http://localhost:3000/ > /dev/null 2>&1; then
            FRONTEND_READY=1
            echo ""
            _info "Frontend ready! (${i}s)"
        fi
    fi

    if [ "$BACKEND_READY" -eq 1 ] && [ "$FRONTEND_READY" -eq 1 ]; then
        break
    fi

    if ! kill -0 $BACKEND_PID 2>/dev/null && [ "$BACKEND_READY" -eq 0 ]; then
        echo ""
        echo ""
        echo "ERROR: Backend exited unexpectedly. Log:"
        cat "$BACKEND_LOG"
        rm -f "$BACKEND_LOG"
        kill $FRONTEND_PID 2>/dev/null
        rm -f "$FRONTEND_LOG"
        exit 1
    fi
    if ! kill -0 $FRONTEND_PID 2>/dev/null && [ "$FRONTEND_READY" -eq 0 ]; then
        echo ""
        echo ""
        echo "ERROR: Frontend exited unexpectedly. Log:"
        cat "$FRONTEND_LOG"
        rm -f "$FRONTEND_LOG"
        kill $BACKEND_PID 2>/dev/null
        rm -f "$BACKEND_LOG"
        exit 1
    fi

    echo -n "."
done

if [ "$BACKEND_READY" -eq 0 ]; then
    echo ""
    echo ""
    echo "ERROR: Backend did not respond within 300 seconds. Log:"
    cat "$BACKEND_LOG"
    rm -f "$BACKEND_LOG"
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    rm -f "$FRONTEND_LOG"
    exit 1
fi

if [ "$FRONTEND_READY" -eq 0 ]; then
    echo ""
    echo ""
    echo "ERROR: Frontend did not respond within 300 seconds."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    rm -f "$BACKEND_LOG" "$FRONTEND_LOG"
    exit 1
fi

echo "Backend is running at http://localhost:8000"
echo "Frontend is running at http://localhost:3000"

# ── Open browser ───────────────────────────────────────────
echo ""
echo "Opening browser..."
open http://localhost:3000

echo ""
echo "Both servers are running. Press Ctrl+C to stop."

# ── Clean shutdown ─────────────────────────────────────────
_cleanup() {
    echo ""
    echo "Stopping servers..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    wait $BACKEND_PID $FRONTEND_PID 2>/dev/null
    rm -f "$BACKEND_LOG" "$FRONTEND_LOG"
    exit 0
}
trap _cleanup INT TERM
wait
