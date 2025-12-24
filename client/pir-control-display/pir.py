#!/usr/bin/env python3
from gpiozero import MotionSensor
import subprocess
import time
import signal
import os
from threading import Timer

# === Default Config ===
# These defaults are used if config file is missing or invalid
DEFAULT_SHUTOFF_DELAY = 5 * 60  # seconds (5 minutes)
DEFAULT_PIR_PIN = 24  # GPIO pin
DEFAULT_DEBUG = False
VCGENCMD = "/usr/bin/vcgencmd"  # Standard Raspberry Pi location
# ======================


def load_config():
    """Load configuration from config.conf file.

    Returns dict with keys: SHUTOFF_DELAY, PIR_PIN, DEBUG
    Falls back to defaults if config is missing or invalid.
    """
    config = {
        "SHUTOFF_DELAY": DEFAULT_SHUTOFF_DELAY,
        "PIR_PIN": DEFAULT_PIR_PIN,
        "DEBUG": DEFAULT_DEBUG,
    }

    # Find config file relative to this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(script_dir, "..", "config.conf")

    if not os.path.exists(config_path):
        print(f"[CONFIG] Config file not found: {config_path}, using defaults")
        return config

    try:
        with open(config_path, "r") as f:
            raw_config = {}
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith("#"):
                    continue
                # Parse KEY=VALUE format
                if "=" in line:
                    key, value = line.split("=", 1)
                    raw_config[key.strip()] = value.strip()

        # Parse PIR_TIMEOUT_MINUTES (convert to seconds)
        if "PIR_TIMEOUT_MINUTES" in raw_config:
            try:
                minutes = int(raw_config["PIR_TIMEOUT_MINUTES"])
                if minutes > 0:
                    config["SHUTOFF_DELAY"] = minutes * 60
                    print(
                        f"[CONFIG] PIR timeout: {minutes} minutes ({config['SHUTOFF_DELAY']}s)"
                    )
                else:
                    print(
                        f"[CONFIG] Invalid PIR_TIMEOUT_MINUTES: {minutes}, using default"
                    )
            except ValueError:
                print(
                    f"[CONFIG] Invalid PIR_TIMEOUT_MINUTES: {raw_config['PIR_TIMEOUT_MINUTES']}, using default"
                )

        # Parse PIR_GPIO_PIN
        if "PIR_GPIO_PIN" in raw_config:
            try:
                pin = int(raw_config["PIR_GPIO_PIN"])
                if 1 <= pin <= 27:  # Valid BCM GPIO range
                    config["PIR_PIN"] = pin
                    print(f"[CONFIG] PIR GPIO pin: {pin}")
                else:
                    print(f"[CONFIG] Invalid PIR_GPIO_PIN: {pin}, using default")
            except ValueError:
                print(
                    f"[CONFIG] Invalid PIR_GPIO_PIN: {raw_config['PIR_GPIO_PIN']}, using default"
                )

        # Parse DEBUG flag
        if "DEBUG" in raw_config:
            debug_str = raw_config["DEBUG"].lower()
            config["DEBUG"] = debug_str == "true"
            print(f"[CONFIG] Debug mode: {config['DEBUG']}")

        print(f"[CONFIG] Configuration loaded from {config_path}")

    except Exception as e:
        print(f"[CONFIG] Error reading config file: {e}, using defaults")

    return config


# Load configuration
config = load_config()
SHUTOFF_DELAY = config["SHUTOFF_DELAY"]
PIR_PIN = config["PIR_PIN"]
DEBUG = config["DEBUG"]

monitor_off = True  # cached state
shutdown_timer = None
running = True


def log(msg):
    if DEBUG:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def display_power(state: int) -> bool:
    try:
        subprocess.run(
            [VCGENCMD, "display_power", str(state)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def read_display_state() -> bool:
    """Return True if display is off, False if on (best-effort)."""
    try:
        result = subprocess.run(
            [VCGENCMD, "display_power"], capture_output=True, text=True, check=True
        )
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
