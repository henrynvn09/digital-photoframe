#!/bin/bash
# Robust MagicMirror startup with PIR control (client-only)
# Fixed version: Uses npm scripts instead of direct Electron launch
# This resolves the "clientonly is not running code null" error

set -euo pipefail
IFS=$'\n\t'

# Configuration
HOME_DIR="${HOME}"
MM_DIR="${HOME_DIR}/MagicMirror"
CONFIG_DIR="${HOME_DIR}/Code/digital-photoframe/client"
ADDRESS="192.168.4.45"
PORT="8036"
PID_DIR="/tmp"
LOCK_DIR="/tmp/mm_instance.lock"
MM_PID_FILE="${PID_DIR}/mm.pid"
PIR_PID_FILE="${PID_DIR}/pir.pid"

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
			sleep 2
			# Force kill if still running
			if kill -0 "${pid}" 2>/dev/null; then
				log "Force killing MagicMirror (PID ${pid})"
				kill -9 "${pid}" 2>/dev/null || true
			fi
		fi
		rm -f "${MM_PID_FILE}"
	fi

	if [[ -f "${PIR_PID_FILE}" ]]; then
		local pid
		pid=$(cat "${PIR_PID_FILE}" 2>/dev/null || true)
		if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
			log "Stopping PIR control (PID ${pid})"
			kill "${pid}" 2>/dev/null || true
			sleep 1
			# Force kill if still running
			if kill -0 "${pid}" 2>/dev/null; then
				log "Force killing PIR control (PID ${pid})"
				kill -9 "${pid}" 2>/dev/null || true
			fi
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
				log "Existing ${expected} process already running (PID ${pid}); killing it for fresh start."
				kill "${pid}" 2>/dev/null || true
				sleep 2
				# Force kill if still alive
				if kill -0 "${pid}" 2>/dev/null; then
					kill -9 "${pid}" 2>/dev/null || true
				fi
			else
				log "Stale PID file ${file} (PID ${pid} is ${comm}); removing."
			fi
		else
			log "PID in ${file} not valid; removing."
		fi
		rm -f "${file}" 2>/dev/null || true
	fi
}

# Pre-start validation: clear stale PID files and kill old processes
validate_pid "${MM_PID_FILE}" "electron\|node"
validate_pid "${PIR_PID_FILE}" "python"

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

# Turn off display initially (let PIR turn it on)
if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
	/usr/bin/vcgencmd display_power 0 2>/dev/null || log "Warning: vcgencmd failed (display may not power off)."
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
	npm run start:x11 >> /tmp/magicmirror.log 2>&1 &
	MM_PID=$!
else
	# Fallback: direct electron launch (for older MagicMirror versions)
	log "Using direct electron launch (fallback method)"
	./node_modules/.bin/electron js/electron.js >> /tmp/magicmirror.log 2>&1 &
	MM_PID=$!
fi

echo "${MM_PID}" > "${MM_PID_FILE}"
log "MagicMirror started (PID ${MM_PID})"

# Give MagicMirror a moment to initialize before starting PIR
sleep 3

# Verify MagicMirror is still running
if ! kill -0 "${MM_PID}" 2>/dev/null; then
	log "ERROR: MagicMirror process died immediately after start!"
	log "Check /tmp/magicmirror.log for errors"
	exit 1
fi

# Start PIR controller
if command -v python3 >/dev/null 2>&1; then
	python3 "${CONFIG_DIR}/pir-control-display/pir.py" >> /tmp/pir.log 2>&1 &
	PIR_PID=$!
	echo "${PIR_PID}" > "${PIR_PID_FILE}"
	log "PIR control started (PID ${PIR_PID})"
else
	log "Warning: python3 not found, PIR control not started"
fi

# Monitor both processes - keep script alive
log "Monitoring processes (MagicMirror: ${MM_PID}, PIR: ${PIR_PID:-none})..."

while true; do
	# Check if MagicMirror is still running
	if ! kill -0 "${MM_PID}" 2>/dev/null; then
		log "ERROR: MagicMirror process (PID ${MM_PID}) has exited unexpectedly!"
		log "Check /tmp/magicmirror.log for errors"
		exit 1
	fi
	
	# Check PIR if it was started
	if [[ -n "${PIR_PID:-}" ]] && ! kill -0 "${PIR_PID}" 2>/dev/null; then
		log "WARNING: PIR process (PID ${PIR_PID}) has exited, restarting..."
		python3 "${CONFIG_DIR}/pir-control-display/pir.py" >> /tmp/pir.log 2>&1 &
		PIR_PID=$!
		echo "${PIR_PID}" > "${PIR_PID_FILE}"
		log "PIR control restarted (PID ${PIR_PID})"
	fi
	
	# Sleep for 30 seconds before next check
	sleep 30
done
