#!/bin/bash
# Optimized MagicMirror startup with PIR control

# Configuration
HOME_DIR="$HOME"
MM_DIR="$HOME_DIR/MagicMirror"
CONFIG_DIR="$HOME_DIR/config-MagicMirror/client"
ADDRESS="192.168.4.45"
PORT="8036"
PID_DIR="/tmp"

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up processes..."
    [[ -f "$PID_DIR/mm.pid" ]] && kill "$(cat "$PID_DIR/mm.pid")" 2>/dev/null
    [[ -f "$PID_DIR/pir.pid" ]] && kill "$(cat "$PID_DIR/pir.pid")" 2>/dev/null
    rm -f "$PID_DIR/mm.pid" "$PID_DIR/pir.pid"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Turn off display initially
/usr/bin/vcgencmd display_power 0

# Start MagicMirror
echo "Starting MagicMirror on $ADDRESS:$PORT..."
cd "$MM_DIR" || exit 1

node clientonly --address "$ADDRESS" --port "$PORT" &
MM_PID=$!
echo "$MM_PID" > "$PID_DIR/mm.pid"
echo "MagicMirror started with PID $MM_PID"

# Start PIR control
python3 "$CONFIG_DIR/pir-control-display/pir.py" &
PIR_PID=$!
echo "$PIR_PID" > "$PID_DIR/pir.pid"
echo "PIR control started with PID $PIR_PID"

# Wait for processes
wait

