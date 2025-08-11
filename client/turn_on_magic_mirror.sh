#!/bin/bash
# save as /home/pi/display_off.sh
export DISPLAY=:0
ADDRESS="192.168.4.45"
PORT="8036"

# Turn off HDMI display
/usr/bin/vcgencmd display_power 0

# Start MagicMirror via PM2
echo "Starting MagicMirror on address $ADDRESS and port $PORT..."
cd $HOME/MagicMirror
nohup node clientonly --address "$ADDRESS" --port "$PORT" &

# Store the PID of the last background command in a temporary file
echo $! > /tmp/mm.pid
echo "MagicMirror started with PID $(cat /tmp/mm.pid)"

# run PIR script to turn monitor on
nohup python3 $HOME/config-MagicMirror/client/pir-control-display/pir.py > $HOME/pir.log 2>&1 &
echo $! > /tmp/pir.pid

