#!/bin/bash
# save as /home/pi/display_off.sh
export DISPLAY=:0

# Start MagicMirror via PM2
/usr/local/bin/pm2 start mm

# Turn on HDMI display
/usr/bin/vcgencmd display_power 1

