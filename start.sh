#!/bin/bash
# Installs all dependencies and starts both servers.
# Usage: bash start.sh

set -e

# Activate project virtual environment if present
if [ -d ".venv" ]; then
    echo "Activating virtual environment..."
    source .venv/bin/activate
fi

# ── Backend Python dependencies ────────────────────────────
echo ""
echo "Installing backend Python dependencies..."
pip install -r requirements.txt

# ── Frontend Node.js dependencies ─────────────────────────
echo ""
echo "Installing frontend Node.js dependencies..."
(cd frontend && npm install)

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
