#!/bin/bash
# Manual display control - Turn off HDMI display
export DISPLAY=:0

# Turn off HDMI display
/usr/bin/vcgencmd display_power 0
