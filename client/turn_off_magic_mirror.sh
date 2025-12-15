#!/bin/bash
# Robust MagicMirror shutdown script with process validation and force-kill
set -euo pipefail
IFS=$'\n\t'

PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
PID_FILE="${PID_DIR}/mm_pids.txt"
KILL_TIMEOUT=5  # seconds to wait before force-kill

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Try to power off display
if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
	/usr/bin/vcgencmd display_power 0 2>/dev/null || log "Warning: vcgencmd failed (display may already be off)."
fi

kill_process() {
	# Args: pid expected_substring human_name
	local pid="$1" expected="$2" name="$3"
	
	if [[ -z "${pid}" ]]; then
		log "No PID provided for ${name}"
		return 0
	fi
	
	if ! kill -0 "${pid}" 2>/dev/null; then
		log "${name} (PID ${pid}) not running"
		return 0
	fi
	
	local comm
	comm=$(ps -p "${pid}" -o comm= 2>/dev/null || true)
	
	if [[ -n "${expected}" ]] && [[ "${comm}" != *"${expected}"* ]]; then
		log "WARNING: PID ${pid} does not appear to be ${name} (found '${comm}')"
		log "Killing anyway for safety..."
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
}

# Read PIDs from file
if [[ -f "${PID_FILE}" ]]; then
	log "Reading PIDs from ${PID_FILE}"
	NPM_PID=$(grep "^NPM:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
	ELECTRON_PID=$(grep "^ELECTRON:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
	PIR_PID=$(grep "^PIR:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
	
	# Kill in order: PIR → Electron → npm parent
	
	# 1. Stop PIR first (so it doesn't try to turn display back on)
	if [[ -n "${PIR_PID}" ]]; then
		kill_process "${PIR_PID}" "python" "PIR control"
	fi
	
	# 2. Stop Electron (main MagicMirror process)
	if [[ -n "${ELECTRON_PID}" ]]; then
		kill_process "${ELECTRON_PID}" "electron\|node" "MagicMirror (electron)"
		
		# Kill any child processes of electron (orphaned chromium/gpu processes)
		local children
		children=$(pgrep -P "${ELECTRON_PID}" 2>/dev/null || true)
		if [[ -n "${children}" ]]; then
			log "Killing child processes of electron: ${children}"
			echo "${children}" | xargs kill -9 2>/dev/null || true
		fi
	fi
	
	# 3. Stop npm parent (cleanup)
	if [[ -n "${NPM_PID}" ]] && [[ "${NPM_PID}" != "${ELECTRON_PID}" ]]; then
		# Only kill npm if it's different from electron (i.e., npm launch method was used)
		if kill -0 "${NPM_PID}" 2>/dev/null; then
			log "Stopping npm parent process (PID ${NPM_PID})"
			kill "${NPM_PID}" 2>/dev/null || true
		fi
	fi
	
	# Aggressive cleanup: kill any remaining electron processes
	pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	
	# Remove PID file
	rm -f "${PID_FILE}"
	
elif [[ -f "/tmp/mm.pid" ]] || [[ -f "/tmp/pir.pid" ]]; then
	# Backward compatibility: handle old PID files
	log "Found old PID files, cleaning up..."
	
	if [[ -f "/tmp/pir.pid" ]]; then
		PIR_PID=$(cat /tmp/pir.pid 2>/dev/null || true)
		if [[ -n "${PIR_PID}" ]]; then
			kill_process "${PIR_PID}" "python" "PIR control"
		fi
		rm -f /tmp/pir.pid
	fi
	
	if [[ -f "/tmp/mm.pid" ]]; then
		MM_PID=$(cat /tmp/mm.pid 2>/dev/null || true)
		if [[ -n "${MM_PID}" ]]; then
			# Old file might have npm or electron PID, so no validation
			kill_process "${MM_PID}" "" "MagicMirror"
		fi
		rm -f /tmp/mm.pid
	fi
	
	# Aggressive cleanup
	pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	
else
	log "No PID file found, attempting aggressive cleanup..."
	# Fallback: kill any electron/pir processes we can find
	pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	pkill -9 -f "pir.py" 2>/dev/null || true
fi

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
