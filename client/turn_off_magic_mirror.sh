#!/bin/bash
# save as /home/pi/display_off.sh
export DISPLAY=:0

# Turn off HDMI display
/usr/bin/vcgencmd display_power 0

# Stop MagicMirror via PM2
echo "Stopping MagicMirror..."
# Check if the pid file exists
if [ -f "/tmp/mm.pid" ]; then
    PID=$(cat /tmp/mm.pid)
    if [ -n "$PID" ]; then
        echo "Killing MagicMirror process with PID: $PID"
        kill "$PID"
        
        # Remove the pid file after killing the process
        rm /tmp/mm.pid
        echo "Process terminated and pid file removed."
    else
        echo "Pid file is empty, no process to kill."
    fi
else
    echo "No pid file found. Is MagicMirror running?"
fi



# Kill pir.py using saved PID
if [[ -f /tmp/pir.pid ]]; then
  pid=$(cat /tmp/pir.pid)
  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping PIR"
    kill "$pid"
    rm /tmp/pir.pid
  fi
fi

