#!/bin/bash
# MagicMirror client-only startup (Raspberry Pi)
# Updated version with server connectivity check and forced X11 mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MM_DIR="${HOME}/MagicMirror"
SERVER_IP="192.168.4.45"
SERVER_PORT="8036"
CONFIG_DIR="${SCRIPT_DIR}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Check if server is reachable before starting
if [[ -f "${CONFIG_DIR}/check_server.sh" ]]; then
	log "Checking server connectivity before starting..."
	if ! "${CONFIG_DIR}/check_server.sh" 5 3; then
		log "ERROR: MagicMirror server at ${SERVER_IP}:${SERVER_PORT} is not reachable!"
		exit 1
	fi
else
	log "Warning: check_server.sh not found, skipping connectivity check"
fi

# Prepare config/env for Electron client-only viewer
export clientonly=1
export config="{\"address\":\"${SERVER_IP}\",\"port\":${SERVER_PORT}}"

cd "$MM_DIR" || exit 1

# Force X11 mode for Raspberry Pi 3B (better performance than Wayland)
export DISPLAY="${DISPLAY:-:0}"

log "Starting MagicMirror client (X11 mode) connecting to ${SERVER_IP}:${SERVER_PORT}..."

# Use npm script for X11 (most reliable method)
exec npm run start:x11
