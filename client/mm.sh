#!/bin/bash
# Optimized MagicMirror client startup script

MM_DIR="/home/hthh/MagicMirror"
SERVER_IP="192.168.1.5"
SERVER_PORT="8036"

cd "$MM_DIR" || exit 1

# Check for Wayland compositor once
if pgrep -x "xway\|labwc" > /dev/null; then
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    exec npm run start:wayland
else
    export DISPLAY=:0
    exec node clientonly --address "$SERVER_IP" --port "$SERVER_PORT"
fi
