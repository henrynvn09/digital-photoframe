#!/bin/bash
# Optimized MagicMirror shutdown script

PID_DIR="/tmp"

# Turn off display immediately
/usr/bin/vcgencmd display_power 0

# Function to kill process by PID file
kill_by_pidfile() {
    local pidfile="$1"
    local process_name="$2"
    
    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Stopping $process_name (PID: $pid)"
            kill "$pid"
            rm -f "$pidfile"
        else
            echo "$process_name not running or PID invalid"
            rm -f "$pidfile"
        fi
    else
        echo "No $process_name PID file found"
    fi
}

# Stop processes
kill_by_pidfile "$PID_DIR/mm.pid" "MagicMirror"
kill_by_pidfile "$PID_DIR/pir.pid" "PIR control"

echo "Shutdown complete"

