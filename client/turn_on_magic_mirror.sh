#!/bin/bash
# MagicMirror Manual Startup Script
#
# NOTE: This script is for MANUAL/DEBUG USE ONLY
# For automatic scheduling, use systemd timers (configured via setup_client.sh)
#
# This script:
# - Starts MagicMirror client in client-only mode
# - Starts PIR motion sensor for display control
# - Monitors processes and auto-restarts PIR if it crashes
#
# Usage:
#   ./turn_on_magic_mirror.sh          # Start MagicMirror manually
#
# To stop:
#   ./turn_off_magic_mirror.sh         # Stop MagicMirror manually

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME}"
MM_DIR="${HOME_DIR}/MagicMirror"
CONFIG_DIR="${SCRIPT_DIR}"
ADDRESS="192.168.4.45"
PORT="8036"
PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
PID_FILE="${PID_DIR}/mm_pids.txt"

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

	# Read PIDs from file
	if [[ -f "${PID_FILE}" ]]; then
		local npm_pid electron_pid pir_pid
		npm_pid=$(grep "^NPM:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		electron_pid=$(grep "^ELECTRON:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		pir_pid=$(grep "^PIR:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		
		# Stop PIR first
		if [[ -n "${pir_pid}" ]] && kill -0 "${pir_pid}" 2>/dev/null; then
			log "Stopping PIR control (PID ${pir_pid})"
			kill "${pir_pid}" 2>/dev/null || true
			sleep 1
			if kill -0 "${pir_pid}" 2>/dev/null; then
				kill -9 "${pir_pid}" 2>/dev/null || true
			fi
		fi
		
		# Stop electron
		if [[ -n "${electron_pid}" ]] && kill -0 "${electron_pid}" 2>/dev/null; then
			log "Stopping electron (PID ${electron_pid})"
			kill "${electron_pid}" 2>/dev/null || true
			sleep 2
			if kill -0 "${electron_pid}" 2>/dev/null; then
				log "Force killing electron (PID ${electron_pid})"
				kill -9 "${electron_pid}" 2>/dev/null || true
			fi
		fi
		
		# Stop npm parent
		if [[ -n "${npm_pid}" ]] && kill -0 "${npm_pid}" 2>/dev/null; then
			log "Stopping npm (PID ${npm_pid})"
			kill "${npm_pid}" 2>/dev/null || true
		fi
		
		rm -f "${PID_FILE}"
	fi

	log "Cleanup complete"
}
trap cleanup EXIT INT TERM

validate_old_processes() {
	# Clean up any old PID files or running processes
	if [[ -f "${PID_FILE}" ]]; then
		log "Found existing PID file, cleaning up old processes..."
		local npm_pid electron_pid pir_pid
		npm_pid=$(grep "^NPM:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		electron_pid=$(grep "^ELECTRON:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		pir_pid=$(grep "^PIR:" "${PID_FILE}" 2>/dev/null | cut -d: -f2)
		
		# Kill PIR if running
		if [[ -n "${pir_pid}" ]] && kill -0 "${pir_pid}" 2>/dev/null; then
			log "Stopping old PIR process (PID ${pir_pid})"
			kill -9 "${pir_pid}" 2>/dev/null || true
		fi
		
		# Kill electron if running
		if [[ -n "${electron_pid}" ]] && kill -0 "${electron_pid}" 2>/dev/null; then
			log "Stopping old electron process (PID ${electron_pid})"
			kill -9 "${electron_pid}" 2>/dev/null || true
		fi
		
		# Kill npm if running
		if [[ -n "${npm_pid}" ]] && kill -0 "${npm_pid}" 2>/dev/null; then
			log "Stopping old npm process (PID ${npm_pid})"
			kill -9 "${npm_pid}" 2>/dev/null || true
		fi
		
		rm -f "${PID_FILE}"
	fi
	
	# Also check for old format PID files
	if [[ -f "/tmp/mm.pid" ]]; then
		local old_pid
		old_pid=$(cat /tmp/mm.pid 2>/dev/null || true)
		if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
			log "Stopping old MagicMirror process from legacy PID file (PID ${old_pid})"
			kill -9 "${old_pid}" 2>/dev/null || true
		fi
		rm -f /tmp/mm.pid
	fi
	
	if [[ -f "/tmp/pir.pid" ]]; then
		local old_pid
		old_pid=$(cat /tmp/pir.pid 2>/dev/null || true)
		if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
			log "Stopping old PIR process from legacy PID file (PID ${old_pid})"
			kill -9 "${old_pid}" 2>/dev/null || true
		fi
		rm -f /tmp/pir.pid
	fi
}

# Pre-start validation: clear old processes
validate_old_processes

# Ensure MagicMirror directory exists
if [[ ! -d "${MM_DIR}" ]]; then
	log "MagicMirror directory not found: ${MM_DIR}" >&2
	exit 1
fi

# Check server connectivity before starting
log "Checking MagicMirror server connectivity..."
if ! "${CONFIG_DIR}/check_server.sh" 5 3; then
	log "ERROR: Cannot reach MagicMirror server at ${ADDRESS}:${PORT}"
	exit 1
fi

# Turn on display when starting MagicMirror
if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
	/usr/bin/vcgencmd display_power 1 2>/dev/null || log "Warning: vcgencmd failed (display may not power on)."
fi

log "Starting MagicMirror (client-only) to ${ADDRESS}:${PORT}..."

# Set up environment for client-only mode
export clientonly=1
export config="{\"address\":\"${ADDRESS}\",\"port\":${PORT}}"
export DISPLAY="${DISPLAY:-:0}"

# Force X11 mode (best for Raspberry Pi 3B)
cd "${MM_DIR}" || exit 1

# Use npm script method (same as mm.sh) - this is the CORRECT way
# This avoids the "clientonly is not running code null" error
if [[ -f "${MM_DIR}/package.json" ]] && grep -q "start:x11" "${MM_DIR}/package.json" 2>/dev/null; then
	log "Using npm run start:x11 (recommended method)"
	npm run start:x11 &
	NPM_PID=$!
	
	# Wait for electron child to spawn (with timeout)
	log "Waiting for electron process to start..."
	ELECTRON_PID=""
	for i in {1..10}; do
		sleep 0.5
		# Find electron child process of npm
		ELECTRON_PID=$(pgrep -P "${NPM_PID}" 2>/dev/null | head -1)
		if [[ -n "${ELECTRON_PID}" ]]; then
			break
		fi
	done
	
	# Verify we found electron
	if [[ -z "${ELECTRON_PID}" ]]; then
		log "ERROR: Could not find electron child process after 5 seconds!"
		log "npm PID ${NPM_PID} may have failed to spawn electron"
		log "Check output above for errors or run with journalctl if using systemd"
		kill "${NPM_PID}" 2>/dev/null || true
		exit 1
	fi
	
	# Save both PIDs to file
	cat > "${PID_FILE}" << EOF
NPM:${NPM_PID}
ELECTRON:${ELECTRON_PID}
EOF
	log "MagicMirror started - npm PID: ${NPM_PID}, electron PID: ${ELECTRON_PID}"
	
else
	# Fallback: direct electron launch (for older MagicMirror versions)
	log "Using direct electron launch (fallback method)"
	./node_modules/.bin/electron js/electron.js &
	ELECTRON_PID=$!
	
	# For direct launch, npm PID is same as electron PID (no parent)
	cat > "${PID_FILE}" << EOF
NPM:${ELECTRON_PID}
ELECTRON:${ELECTRON_PID}
EOF
	log "MagicMirror started (PID ${ELECTRON_PID})"
fi

# Give MagicMirror a moment to initialize before starting PIR
sleep 3

# Verify electron is still running
if ! kill -0 "${ELECTRON_PID}" 2>/dev/null; then
	log "ERROR: Electron process died immediately after start!"
	log "Check output above for errors or run with journalctl if using systemd"
	exit 1
fi

# Start PIR controller
if command -v python3 >/dev/null 2>&1; then
	python3 "${CONFIG_DIR}/pir-control-display/pir.py" &
	PIR_PID=$!
	
	# Append PIR PID to same file
	echo "PIR:${PIR_PID}" >> "${PID_FILE}"
	log "PIR control started (PID ${PIR_PID})"
else
	log "Warning: python3 not found, PIR control not started"
fi

# Monitor both processes - keep script alive
log "Monitoring processes (npm: ${NPM_PID}, electron: ${ELECTRON_PID}, PIR: ${PIR_PID:-none})..."

while true; do
	# Check if electron is still running (main process)
	if ! kill -0 "${ELECTRON_PID}" 2>/dev/null; then
		log "ERROR: Electron process (PID ${ELECTRON_PID}) has exited unexpectedly!"
		log "Check output above for errors or run with journalctl if using systemd"
		
		# Clean up npm parent if still running
		if [[ "${NPM_PID}" != "${ELECTRON_PID}" ]] && kill -0 "${NPM_PID}" 2>/dev/null; then
			log "Stopping orphaned npm process (PID ${NPM_PID})"
			kill "${NPM_PID}" 2>/dev/null || true
		fi
		
		exit 1
	fi
	
	# Check PIR if it was started
	if [[ -n "${PIR_PID:-}" ]] && ! kill -0 "${PIR_PID}" 2>/dev/null; then
		log "WARNING: PIR process (PID ${PIR_PID}) has exited, restarting..."
		python3 "${CONFIG_DIR}/pir-control-display/pir.py" &
		PIR_PID=$!
		
		# Update PID file (remove old PIR line, add new one)
		grep -v "^PIR:" "${PID_FILE}" > "${PID_FILE}.tmp" 2>/dev/null || true
		echo "PIR:${PIR_PID}" >> "${PID_FILE}.tmp"
		mv "${PID_FILE}.tmp" "${PID_FILE}"
		
		log "PIR control restarted (PID ${PIR_PID})"
	fi
	
	# Sleep for 30 seconds before next check
	sleep 30
done
