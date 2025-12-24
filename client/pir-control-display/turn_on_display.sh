#!/bin/bash
# Manual display control - Turn on HDMI display
export DISPLAY=:0

# Turn on HDMI display
/usr/bin/vcgencmd display_power 1
