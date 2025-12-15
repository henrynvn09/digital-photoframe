#!/bin/bash
# Server connectivity checker for MagicMirror
# Returns 0 if server is reachable, 1 if not
# Usage: ./check_server.sh [max_attempts] [delay_seconds]

set -euo pipefail

SERVER_IP="192.168.4.45"
SERVER_PORT="8036"
MAX_ATTEMPTS="${1:-5}"
DELAY="${2:-3}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_server() {
	# Try to connect to the server using timeout and nc (netcat)
	if command -v nc >/dev/null 2>&1; then
		timeout 2 nc -z "${SERVER_IP}" "${SERVER_PORT}" 2>/dev/null
		return $?
	elif command -v curl >/dev/null 2>&1; then
		# Fallback to curl if nc not available
		timeout 2 curl -s "http://${SERVER_IP}:${SERVER_PORT}" >/dev/null 2>&1
		return $?
	else
		# Last resort: use /dev/tcp (bash built-in)
		timeout 2 bash -c "echo > /dev/tcp/${SERVER_IP}/${SERVER_PORT}" 2>/dev/null
		return $?
	fi
}

# Main loop
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
	log "Checking server connectivity (attempt ${i}/${MAX_ATTEMPTS})..."
	
	if check_server; then
		log "Server ${SERVER_IP}:${SERVER_PORT} is reachable!"
		exit 0
	else
		if [[ ${i} -lt ${MAX_ATTEMPTS} ]]; then
			log "Server unreachable, retrying in ${DELAY} seconds..."
			sleep "${DELAY}"
		fi
	fi
done

log "ERROR: Server ${SERVER_IP}:${SERVER_PORT} unreachable after ${MAX_ATTEMPTS} attempts"
exit 1
