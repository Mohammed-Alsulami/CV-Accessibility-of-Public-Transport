#!/bin/bash
# Starts the backend (FastAPI) and frontend (React) servers.
# Usage: bash start.sh

PYTHON=/opt/homebrew/bin/python3.14

# ── Virtual environment ────────────────────────────────────
if [ ! -d ".venv" ] || [ ! -f ".venv/bin/activate" ]; then
    echo "Creating virtual environment..."
    "$PYTHON" -m venv .venv
    echo "Virtual environment created ($(.venv/bin/python --version 2>&1))."
fi

echo "Activating virtual environment..."
source .venv/bin/activate

# ── Backend Python dependencies ────────────────────────────
SITE_PACKAGES=$(python -c "import sysconfig; print(sysconfig.get_path('purelib'))" 2>/dev/null)

_pkg_installed() {
    [ -d "${SITE_PACKAGES}/${1}" ] || ls "${SITE_PACKAGES}/${1}"-*.dist-info 2>/dev/null | grep -q .
}

if [ ! -f .venv/.deps-installed ] || [ requirements.txt -nt .venv/.deps-installed ]; then
    if _pkg_installed torch && _pkg_installed fastapi && _pkg_installed uvicorn && \
       _pkg_installed opencv_python && _pkg_installed reportlab; then
        echo "Backend dependencies already installed."
        touch .venv/.deps-installed
    else
        echo ""
        echo "Installing backend Python dependencies..."
        echo "(PyTorch is large — this may take several minutes on first install)"
        pip install -r requirements.txt && touch .venv/.deps-installed
    fi
else
    echo "Backend dependencies up to date."
fi

# ── Frontend Node.js dependencies ─────────────────────────
if [ ! -d frontend/node_modules ] || \
   [ frontend/package.json -nt frontend/node_modules/.install-stamp ] || \
   { [ -f frontend/package-lock.json ] && [ frontend/package-lock.json -nt frontend/node_modules/.install-stamp ]; }; then
    echo ""
    echo "Installing frontend Node.js dependencies..."
    (cd frontend && npm ci 2>/dev/null || npm install) && touch frontend/node_modules/.install-stamp
else
    echo "Frontend dependencies up to date."
fi

# ── Clear ports if already occupied ───────────────────────
echo ""
for port in 8000 3000; do
    pids=$(lsof -ti :"$port" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "Freeing port $port..."
        echo "$pids" | xargs kill 2>/dev/null || true
        sleep 1
        lsof -ti :"$port" 2>/dev/null | xargs kill -9 2>/dev/null || true
    fi
done

# ── Start backend ──────────────────────────────────────────
echo ""
echo "Starting backend  →  http://localhost:8000"
echo "(PyTorch model loading may take ~30-60 seconds on first start)"

BACKEND_LOG="$(pwd)/.venv/backend_run.log"
(cd backend && PYTHONUNBUFFERED=1 python -m uvicorn main:app --host 127.0.0.1 --port 8000 2>&1 | tee "$BACKEND_LOG") &
BACKEND_PID=$!

# Wait for backend to accept connections (up to 120 seconds)
echo -n "  Waiting for backend"
BACKEND_READY=0
for i in $(seq 1 120); do
    sleep 1
    if curl -sf http://127.0.0.1:8000/ > /dev/null 2>&1; then
        BACKEND_READY=1
        echo " ready! (${i}s)"
        break
    fi
    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo ""
        echo ""
        echo "ERROR: Backend exited unexpectedly. Log:"
        cat "$BACKEND_LOG"
        rm -f "$BACKEND_LOG"
        exit 1
    fi
    echo -n "."
done

if [ "$BACKEND_READY" -eq 0 ]; then
    echo ""
    echo ""
    echo "ERROR: Backend did not respond within 120 seconds. Log:"
    cat "$BACKEND_LOG"
    rm -f "$BACKEND_LOG"
    kill $BACKEND_PID 2>/dev/null
    exit 1
fi

echo "Backend is running at http://localhost:8000"

# ── Start frontend ─────────────────────────────────────────
echo ""
echo "Starting frontend →  http://localhost:3000"

(cd frontend && BROWSER=none npm start 2>&1) &
FRONTEND_PID=$!

# Wait for frontend to be ready (up to 120 seconds)
echo -n "  Waiting for frontend"
FRONTEND_READY=0
for i in $(seq 1 120); do
    sleep 1
    if curl -sf http://localhost:3000/ > /dev/null 2>&1; then
        FRONTEND_READY=1
        echo " ready! (${i}s)"
        break
    fi
    if ! kill -0 $FRONTEND_PID 2>/dev/null; then
        echo ""
        echo ""
        echo "ERROR: Frontend exited unexpectedly."
        kill $BACKEND_PID 2>/dev/null
        rm -f "$BACKEND_LOG"
        exit 1
    fi
    echo -n "."
done

if [ "$FRONTEND_READY" -eq 0 ]; then
    echo ""
    echo ""
    echo "ERROR: Frontend did not respond within 120 seconds."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    rm -f "$BACKEND_LOG"
    exit 1
fi

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
    rm -f "$BACKEND_LOG"
    exit 0
}
trap _cleanup INT TERM
wait
