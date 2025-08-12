#!/bin/bash
# Robust MagicMirror startup with PIR control (Option A: display stays off until motion)
# Adds: DISPLAY export, lock to prevent overlap, stale PID validation, safe cleanup

set -euo pipefail
IFS=$'\n\t'

# Configuration
HOME_DIR="${HOME}"
MM_DIR="${HOME_DIR}/MagicMirror"
CONFIG_DIR="${HOME_DIR}/config-MagicMirror/client"
ADDRESS="192.168.4.45"
PORT="8036"
PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
MM_PID_FILE="${PID_DIR}/mm.pid"
PIR_PID_FILE="${PID_DIR}/pir.pid"

# Environment for graphical session (adjust if using Wayland or different display)
export DISPLAY=:0
# If Wayland only: export WAYLAND_DISPLAY=wayland-0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Acquire lock (mkdir is atomic)
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  log "Startup aborted: lock exists (${LOCK_DIR}). Another instance may be running."
  exit 0
fi

cleanup() {
    local code=$?
    log "Cleanup initiated (exit code ${code})"

    # Remove lock first to allow future starts even if kills fail
    [[ -d "${LOCK_DIR}" ]] && rmdir "${LOCK_DIR}" 2>/dev/null || true

    # Gracefully terminate processes if still running
    if [[ -f "${MM_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${MM_PID_FILE}" 2>/dev/null || true)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log "Stopping MagicMirror (PID ${pid})"
            kill "${pid}" 2>/dev/null || true
        fi
        rm -f "${MM_PID_FILE}"
    fi

    if [[ -f "${PIR_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PIR_PID_FILE}" 2>/dev/null || true)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log "Stopping PIR control (PID ${pid})"
            kill "${pid}" 2>/dev/null || true
        fi
        rm -f "${PIR_PID_FILE}"
    fi

    log "Cleanup complete"
}
trap cleanup EXIT INT TERM

validate_pid() {
    # Args: pid_file expected_substring
    local file="$1" expected="$2"
    if [[ -f "${file}" ]]; then
        local pid
        pid=$(cat "${file}" 2>/dev/null || true)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            local comm
            comm=$(ps -p "${pid}" -o comm= 2>/dev/null || true)
            if [[ "${comm}" == *"${expected}"* ]]; then
                log "Existing ${expected} process already running (PID ${pid}); removing stale file and aborting duplicate start."
                # Intentionally NOT exiting because we want fresh start; kill old
                kill "${pid}" 2>/dev/null || true
            else
                log "Stale PID file ${file} (PID ${pid} is ${comm}); removing."
            fi
        else
            log "PID in ${file} not valid; removing."
        fi
        rm -f "${file}" 2>/dev/null || true
    fi
}

# Pre-start validation: clear stale PID files
validate_pid "${MM_PID_FILE}" node
validate_pid "${PIR_PID_FILE}" python

# Ensure MagicMirror directory exists
if [[ ! -d "${MM_DIR}" ]]; then
  log "MagicMirror directory not found: ${MM_DIR}" >&2
  exit 1
fi

# Turn off display initially (Option A behavior)
/usr/bin/vcgencmd display_power 0 || log "Warning: vcgencmd failed (display may not power off)."

log "Starting MagicMirror on ${ADDRESS}:${PORT}..."
cd "${MM_DIR}" || exit 1

# Start MagicMirror clientonly mode
if command -v node >/dev/null 2>&1; then
  node clientonly --address "${ADDRESS}" --port "${PORT}" &
else
  log "Error: node binary not found in PATH" >&2; exit 1
fi
MM_PID=$!
echo "${MM_PID}" > "${MM_PID_FILE}"
log "MagicMirror started (PID ${MM_PID})"

# Start PIR controller
if command -v python3 >/dev/null 2>&1; then
  python3 "${CONFIG_DIR}/pir-control-display/pir.py" &
else
  log "Error: python3 not found" >&2; exit 1
fi
PIR_PID=$!
echo "${PIR_PID}" > "${PIR_PID_FILE}"
log "PIR control started (PID ${PIR_PID})"

# Wait for either process to exit; then cleanup trap will fire
wait -n || true
log "One process exited; waiting briefly then exiting startup script."
# Optionally: wait for both (commented)
# wait
