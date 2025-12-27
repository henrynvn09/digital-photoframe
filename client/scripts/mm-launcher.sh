#!/bin/bash
# MagicMirror client-only startup (Raspberry Pi)
# Updated version with server connectivity check and forced X11 mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MM_DIR="${HOME}/MagicMirror"
CONFIG_FILE="${CLIENT_DIR}/config.conf"

# Default values (fallback if config missing)
SERVER_IP="192.168.4.45"
SERVER_PORT="8036"

# Load server settings from config file if available
if [[ -f "$CONFIG_FILE" ]]; then
	# shellcheck disable=SC1090
	source "$CONFIG_FILE" 2>/dev/null || true
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Check if server is reachable before starting
if [[ -f "${CLIENT_DIR}/scripts/server-check.sh" ]]; then
	log "Checking server connectivity before starting..."
	if ! "${CLIENT_DIR}/scripts/server-check.sh" 5 3; then
		log "ERROR: MagicMirror server at ${SERVER_IP}:${SERVER_PORT} is not reachable!"
		exit 1
	fi
else
	log "Warning: server-check.sh not found, skipping connectivity check"
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
