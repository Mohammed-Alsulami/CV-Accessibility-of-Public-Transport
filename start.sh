#!/bin/bash
# Installs all dependencies and starts both servers.
# Usage: bash start.sh

set -e

# Create virtual environment if missing, then activate it
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi
echo "Activating virtual environment..."
source .venv/bin/activate

# ── Backend Python dependencies ────────────────────────────
if [ requirements.txt -nt .venv/.deps-installed ]; then
    echo ""
    echo "Installing backend Python dependencies..."
    pip install -r requirements.txt && touch .venv/.deps-installed
else
    echo ""
    echo "Backend dependencies up to date, skipping pip install."
fi

# ── Frontend Node.js dependencies ─────────────────────────
if [ frontend/package.json -nt frontend/node_modules/.install-stamp ] || \
   [ frontend/package-lock.json -nt frontend/node_modules/.install-stamp ] 2>/dev/null; then
    echo ""
    echo "Installing frontend Node.js dependencies..."
    (cd frontend && npm ci 2>/dev/null || npm install) && touch frontend/node_modules/.install-stamp
else
    echo ""
    echo "Frontend dependencies up to date, skipping npm install."
fi

# ── Clear ports if already occupied ───────────────────────
lsof -ti :8000 | xargs kill -9 2>/dev/null || true
lsof -ti :3000 | xargs kill -9 2>/dev/null || true

# ── Start backend ──────────────────────────────────────────
echo ""
echo "Starting backend  →  http://localhost:8000"
echo "(first start may take ~15 seconds while PyTorch loads)"
(cd backend && python -m uvicorn main:app --reload) &
BACKEND_PID=$!

# ── Start frontend ─────────────────────────────────────────
echo "Starting frontend →  http://localhost:3000"
(cd frontend && npm start) &
FRONTEND_PID=$!

echo ""
echo "Both servers are running. Press Ctrl+C to stop both."

# Cleanly stop both servers on Ctrl+C
trap "echo ''; echo 'Stopping servers...'; kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit" INT TERM
wait
