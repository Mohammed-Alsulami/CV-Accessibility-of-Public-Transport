#!/bin/bash
# Installs all dependencies and starts both servers.
# Usage: bash start.sh

set -e

# Activate project virtual environment if present
if [ -d ".venv" ]; then
    echo "Activating virtual environment..."
    source .venv/bin/activate
fi

# ── Backend ────────────────────────────────────────────────
echo ""
echo "Installing backend Python dependencies..."
pip install -r requirements.txt

# ── Frontend ───────────────────────────────────────────────
echo ""
echo "Installing frontend Node.js dependencies..."
(cd frontend && npm install)

# ── Start servers ──────────────────────────────────────────
echo ""
echo "Starting backend  →  http://localhost:8000"
(cd backend && uvicorn main:app --reload) &
BACKEND_PID=$!

echo "Starting frontend →  http://localhost:3000"
(cd frontend && npm start) &
FRONTEND_PID=$!

echo ""
echo "Both servers are running. Press Ctrl+C to stop."

# Cleanly kill both servers on exit
trap "echo ''; echo 'Stopping servers...'; kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit" INT TERM
wait
