#!/bin/bash
# Robust MagicMirror shutdown script with process validation and force-kill
set -euo pipefail
IFS=$'\n\t'

PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
MM_PID_FILE="${PID_DIR}/mm.pid"
PIR_PID_FILE="${PID_DIR}/pir.pid"
KILL_TIMEOUT=5  # seconds to wait before force-kill

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Try to power off display
if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
	/usr/bin/vcgencmd display_power 0 2>/dev/null || log "Warning: vcgencmd failed (display may already be off)."
fi

kill_validated() {
	# Args: pid_file expected_substring human_name
	local file="$1" expected="$2" name="$3"
	
	if [[ ! -f "${file}" ]]; then
		log "No PID file for ${name}"
		return 0
	fi
	
	local pid
	pid=$(cat "${file}" 2>/dev/null || true)
	
	if [[ -z "${pid}" ]]; then
		log "${name} PID file is empty"
		rm -f "${file}" 2>/dev/null || true
		return 0
	fi
	
	if ! kill -0 "${pid}" 2>/dev/null; then
		log "${name} not running (stale PID file)."
		rm -f "${file}" 2>/dev/null || true
		return 0
	fi
	
	local comm
	comm=$(ps -p "${pid}" -o comm= 2>/dev/null || true)
	
	if [[ "${comm}" != *"${expected}"* ]]; then
		log "PID ${pid} in ${file} does not appear to be ${name} (found '${comm}'); skipping kill."
		rm -f "${file}" 2>/dev/null || true
		return 0
	fi
	
	# Graceful shutdown attempt
	log "Stopping ${name} (PID ${pid}) gracefully..."
	kill "${pid}" 2>/dev/null || true
	
	# Wait for graceful shutdown
	local waited=0
	while kill -0 "${pid}" 2>/dev/null && [[ ${waited} -lt ${KILL_TIMEOUT} ]]; do
		sleep 1
		waited=$((waited + 1))
	done
	
	# Force kill if still running
	if kill -0 "${pid}" 2>/dev/null; then
		log "${name} (PID ${pid}) did not stop gracefully, force killing..."
		kill -9 "${pid}" 2>/dev/null || true
		sleep 1
		
		if kill -0 "${pid}" 2>/dev/null; then
			log "ERROR: Could not kill ${name} (PID ${pid})"
		else
			log "${name} force killed successfully"
		fi
	else
		log "${name} stopped gracefully"
	fi
	
	# Kill child processes of the main process (orphaned Electron processes)
	if [[ "${name}" == "MagicMirror" ]]; then
		local children
		children=$(pgrep -P "${pid}" 2>/dev/null || true)
		if [[ -n "${children}" ]]; then
			log "Killing child processes of ${name}: ${children}"
			echo "${children}" | xargs -r kill -9 2>/dev/null || true
		fi
		
		# Also kill any remaining electron/chromium processes (aggressive cleanup)
		pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	fi
	
	rm -f "${file}" 2>/dev/null || true
}

# Stop PIR controller first (so it doesn't try to turn display back on)
kill_validated "${PIR_PID_FILE}" "python" "PIR control"

# Stop MagicMirror viewer (Electron under X11)
kill_validated "${MM_PID_FILE}" "electron\|node" "MagicMirror"

# Remove lock directory if present (in case start script died unexpectedly)
if [[ -d "${LOCK_DIR}" ]]; then
	# Check if lock is stale (older than 5 minutes)
	if [[ -n "$(find "${LOCK_DIR}" -type d -mmin +5 2>/dev/null)" ]]; then
		rmdir "${LOCK_DIR}" 2>/dev/null || true
		log "Removed stale lock directory"
	else
		# Try to remove anyway (may have been left by crashed script)
		if rmdir "${LOCK_DIR}" 2>/dev/null; then
			log "Removed lock directory"
		else
			log "Warning: Could not remove lock directory (may still be in use)"
		fi
	fi
fi

# Clean up any leftover log files older than 7 days
find /tmp -name "magicmirror.log*" -type f -mtime +7 -delete 2>/dev/null || true
find /tmp -name "pir.log*" -type f -mtime +7 -delete 2>/dev/null || true

log "Shutdown complete"
