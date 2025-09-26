#!/usr/bin/env python3
from gpiozero import MotionSensor
import subprocess
import time
import signal
from threading import Timer

# === Config ===
SHUTOFF_DELAY = 15 * 60  # seconds
PIR_PIN = 24  # GPIO pin
DEBUG = False  # set to False to silence debug output
VCGENCMD = "/usr/bin/vcgencmd"
# ==============

monitor_off = True  # cached state
shutdown_timer = None
running = True


def log(msg):
    if DEBUG:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def display_power(state: int) -> bool:
    try:
        subprocess.run([VCGENCMD, "display_power", str(state)],
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL,
                       check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def read_display_state() -> bool:
    """Return True if display is off, False if on (best-effort)."""
    try:
        result = subprocess.run([VCGENCMD, "display_power"], capture_output=True, text=True, check=True)
        # Expected output: display_power=1 or display_power=0
        if "display_power=1" in result.stdout:
            return False
    except Exception:
        pass
    return True  # assume off if uncertain to avoid redundant ON command


def cancel_timer():
    global shutdown_timer
    if shutdown_timer is not None:
        shutdown_timer.cancel()
        shutdown_timer = None


def schedule_shutdown():
    global shutdown_timer
    cancel_timer()
    shutdown_timer = Timer(SHUTOFF_DELAY, power_off_if_idle)
    shutdown_timer.daemon = True
    shutdown_timer.start()
    log(f"No motion - scheduled OFF in {SHUTOFF_DELAY}s")


def power_off_if_idle():
    global monitor_off, shutdown_timer
    # Re-check sensor right before powering off to avoid race
    if not pir.motion_detected and not monitor_off:
        log("Timeout reached - turning OFF")
        if display_power(0):
            monitor_off = True
    shutdown_timer = None


def motion_detected():
    global monitor_off
    cancel_timer()
    if monitor_off:
        log("Motion detected - turning ON")
        if display_power(1):
            monitor_off = False


def no_motion():
    schedule_shutdown()


def signal_handler(signum, frame):
    global running
    log("Received shutdown signal")
    running = False
    cancel_timer()


# Setup signal handlers for clean shutdown
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

# Initialize PIR sensor
pir = MotionSensor(PIR_PIN)
monitor_off = read_display_state()

pir.when_motion = motion_detected
pir.when_no_motion = no_motion

log("PIR monitor control running (event-driven)...")

# Idle here until signals arrive
try:
    while running:
        time.sleep(3600)  # sleep long; events are callback-driven
except KeyboardInterrupt:
    pass
finally:
    log("Shutting down PIR control")
    cancel_timer()
    pir.close()
