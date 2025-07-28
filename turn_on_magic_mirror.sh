#!/bin/bash
# save as /home/pi/display_off.sh
export DISPLAY=:0

# Turn off HDMI display
/usr/bin/vcgencmd display_power 1

# Stop MagicMirror via PM2
/usr/local/bin/pm2 start mm
