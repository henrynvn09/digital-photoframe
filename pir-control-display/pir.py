#!/usr/bin/env python3
from gpiozero import MotionSensor
import subprocess
import time
from threading import Timer
from signal import pause
import os

# === Config ===
SHUTOFF_DELAY = 30*60  # seconds
PIR_PIN = 24         # GPIO pin
DEBUG = False        # set to False to silence debug output
# ==============
path = os.environ.get("PIR_PATH", "/home/hthh/config-MagicMirror")

pir = MotionSensor(PIR_PIN)
monitor_off = True
last_motion = time.time()

def log(msg):
    if DEBUG:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}")

def turn_on():
    log("Turning monitor ON")
    subprocess.run(["sh", os.path.join(path, "pir-control-display/turn_on_display.sh")])

def turn_off():
    log("Turning monitor OFF")
    subprocess.run(["sh", os.path.join(path, "pir-control-display/turn_off_display.sh")])

def motion_detected():
    global monitor_off, last_motion
    last_motion = time.time()
    log("Motion detected")
    if monitor_off:
        monitor_off = False
        turn_on()

def no_motion():
    log(f"No motion, will check again in {SHUTOFF_DELAY}s")
    Timer(SHUTOFF_DELAY, check_and_turn_off).start()

def check_and_turn_off():
    global monitor_off
    if not pir.motion_detected and not monitor_off:
        monitor_off = True
        turn_off()
    else:
        log("Motion resumed before timeout, keeping monitor ON")

pir.when_motion = motion_detected
pir.when_no_motion = no_motion

log("PIR monitor control running...")
pause()  # wait forever with near-zero CPU usage
