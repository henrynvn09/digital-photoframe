#!/bin/bash
# Robust MagicMirror shutdown script with process validation
set -euo pipefail
IFS=$'\n\t'

PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
MM_PID_FILE="${PID_DIR}/mm.pid"
PIR_PID_FILE="${PID_DIR}/pir.pid"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Turn off display immediately
/usr/bin/vcgencmd display_power 0 || log "Warning: vcgencmd failed (display may already be off)."

kill_validated() {
  # Args: pid_file expected_substring human_name
  local file="$1" expected="$2" name="$3"
  if [[ -f "${file}" ]]; then
    local pid
    pid=$(cat "${file}" 2>/dev/null || true)
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      local comm
      comm=$(ps -p "${pid}" -o comm= 2>/dev/null || true)
      if [[ "${comm}" == *"${expected}"* ]]; then
        log "Stopping ${name} (PID ${pid})"
        kill "${pid}" 2>/dev/null || true
      else
        log "PID ${pid} in ${file} does not appear to be ${name} (found '${comm}'); skipping kill."
      fi
    else
      log "${name} not running (stale PID file)."
    fi
    rm -f "${file}" 2>/dev/null || true
  else
    log "No PID file for ${name}" 
  fi
}

kill_validated "${MM_PID_FILE}" node "MagicMirror"
kill_validated "${PIR_PID_FILE}" python "PIR control"

# Remove lock directory if present (in case start script died unexpectedly)
if [[ -d "${LOCK_DIR}" ]]; then
  rmdir "${LOCK_DIR}" 2>/dev/null || true
  log "Removed stale lock directory"
fi

log "Shutdown complete"
