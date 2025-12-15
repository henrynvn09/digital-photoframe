#!/bin/bash
# MagicMirror Schedule Manager
# Runs continuously, starts/stops MagicMirror based on schedule
# This script is managed by systemd (magicmirror.service)

set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MM_DIR="${HOME}/MagicMirror"
SERVER_IP="192.168.4.45"
SERVER_PORT="8036"
SCHEDULE_CONF="${SCRIPT_DIR}/schedule.conf"

# Default schedule (if config file missing or invalid)
DEFAULT_WEEKEND_ON_HOUR=8
DEFAULT_WEEKEND_ON_MIN=0
DEFAULT_WEEKDAY_ON_HOUR=16
DEFAULT_WEEKDAY_ON_MIN=0
DEFAULT_OFF_HOUR=20
DEFAULT_OFF_MIN=45

# State tracking
MM_PID=""
PIR_PID=""
CURRENT_STATE="UNKNOWN"  # Values: OFF, ON, UNKNOWN

# Logging
log() { 
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Load schedule from config file
load_schedule() {
	# Set defaults first
	WEEKEND_ON_HOUR=$DEFAULT_WEEKEND_ON_HOUR
	WEEKEND_ON_MIN=$DEFAULT_WEEKEND_ON_MIN
	WEEKDAY_ON_HOUR=$DEFAULT_WEEKDAY_ON_HOUR
	WEEKDAY_ON_MIN=$DEFAULT_WEEKDAY_ON_MIN
	OFF_HOUR=$DEFAULT_OFF_HOUR
	OFF_MIN=$DEFAULT_OFF_MIN
	
	# Try to load from file
	if [[ -f "$SCHEDULE_CONF" ]]; then
		# Source the file in a subshell to avoid polluting our environment
		# shellcheck disable=SC1090
		source "$SCHEDULE_CONF" || {
			log "Warning: Failed to parse $SCHEDULE_CONF, using defaults"
			return
		}
		
		# Validate values (hours: 0-23, minutes: 0-59)
		if [[ $WEEKEND_ON_HOUR -lt 0 || $WEEKEND_ON_HOUR -gt 23 ]]; then
			log "Warning: Invalid WEEKEND_ON_HOUR=$WEEKEND_ON_HOUR, using default"
			WEEKEND_ON_HOUR=$DEFAULT_WEEKEND_ON_HOUR
		fi
		if [[ $WEEKEND_ON_MIN -lt 0 || $WEEKEND_ON_MIN -gt 59 ]]; then
			log "Warning: Invalid WEEKEND_ON_MIN=$WEEKEND_ON_MIN, using default"
			WEEKEND_ON_MIN=$DEFAULT_WEEKEND_ON_MIN
		fi
		if [[ $WEEKDAY_ON_HOUR -lt 0 || $WEEKDAY_ON_HOUR -gt 23 ]]; then
			log "Warning: Invalid WEEKDAY_ON_HOUR=$WEEKDAY_ON_HOUR, using default"
			WEEKDAY_ON_HOUR=$DEFAULT_WEEKDAY_ON_HOUR
		fi
		if [[ $WEEKDAY_ON_MIN -lt 0 || $WEEKDAY_ON_MIN -gt 59 ]]; then
			log "Warning: Invalid WEEKDAY_ON_MIN=$WEEKDAY_ON_MIN, using default"
			WEEKDAY_ON_MIN=$DEFAULT_WEEKDAY_ON_MIN
		fi
		if [[ $OFF_HOUR -lt 0 || $OFF_HOUR -gt 23 ]]; then
			log "Warning: Invalid OFF_HOUR=$OFF_HOUR, using default"
			OFF_HOUR=$DEFAULT_OFF_HOUR
		fi
		if [[ $OFF_MIN -lt 0 || $OFF_MIN -gt 59 ]]; then
			log "Warning: Invalid OFF_MIN=$OFF_MIN, using default"
			OFF_MIN=$DEFAULT_OFF_MIN
		fi
	else
		log "Warning: Schedule file not found: $SCHEDULE_CONF, using defaults"
	fi
	
	log "Schedule loaded: Weekend ON=${WEEKEND_ON_HOUR}:$(printf '%02d' $WEEKEND_ON_MIN), Weekday ON=${WEEKDAY_ON_HOUR}:$(printf '%02d' $WEEKDAY_ON_MIN), OFF=${OFF_HOUR}:$(printf '%02d' $OFF_MIN)"
}

# Check if MagicMirror should be running based on schedule
# Returns 0 (true) if should be ON, 1 (false) if should be OFF
should_be_running() {
	local hour minute day current_min on_min off_min
	
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)  # 1=Mon, 2=Tue, ... 6=Sat, 7=Sun
	
	# Convert to minutes since midnight (force base-10 to avoid octal issues)
	current_min=$((10#$hour * 60 + 10#$minute))
	off_min=$((OFF_HOUR * 60 + OFF_MIN))
	
	# Determine ON time based on day
	if [[ $day -ge 6 ]]; then
		# Weekend (Sat=6, Sun=7)
		on_min=$((WEEKEND_ON_HOUR * 60 + WEEKEND_ON_MIN))
	else
		# Weekday (Mon=1 through Fri=5)
		on_min=$((WEEKDAY_ON_HOUR * 60 + WEEKDAY_ON_MIN))
	fi
	
	# Check if current time is within ON window
	if [[ $current_min -ge $on_min && $current_min -lt $off_min ]]; then
		return 0  # Should be ON
	else
		return 1  # Should be OFF
	fi
}

# Start MagicMirror and PIR
start_magicmirror() {
	log "Starting MagicMirror..."
	
	# Turn display ON
	if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
		/usr/bin/vcgencmd display_power 1 2>/dev/null || log "Warning: vcgencmd display_power failed"
	fi
	
	# Check server connectivity
	if [[ -f "${SCRIPT_DIR}/check_server.sh" ]]; then
		if ! "${SCRIPT_DIR}/check_server.sh" 10 5; then
			log "ERROR: Server not reachable at ${SERVER_IP}:${SERVER_PORT}, will retry later"
			return 1
		fi
	else
		log "Warning: check_server.sh not found, skipping connectivity check"
	fi
	
	# Start MagicMirror
	if [[ ! -d "$MM_DIR" ]]; then
		log "ERROR: MagicMirror directory not found: $MM_DIR"
		return 1
	fi
	
	cd "$MM_DIR" || return 1
	
	export clientonly=1
	export config="{\"address\":\"${SERVER_IP}\",\"port\":${SERVER_PORT}}"
	export DISPLAY="${DISPLAY:-:0}"
	
	# Start in background, redirect output to log
	npm run start:x11 >> /tmp/magicmirror.log 2>&1 &
	MM_PID=$!
	
	log "MagicMirror started (PID: $MM_PID), waiting for initialization..."
	
	# Wait for electron to spawn
	sleep 3
	
	# Verify MagicMirror is still running
	if ! kill -0 "$MM_PID" 2>/dev/null; then
		log "ERROR: MagicMirror process died immediately after start"
		MM_PID=""
		return 1
	fi
	
	# Start PIR controller
	if [[ -f "${SCRIPT_DIR}/pir-control-display/pir.py" ]]; then
		if command -v python3 >/dev/null 2>&1; then
			python3 "${SCRIPT_DIR}/pir-control-display/pir.py" >> /tmp/pir.log 2>&1 &
			PIR_PID=$!
			log "PIR control started (PID: $PIR_PID)"
		else
			log "Warning: python3 not found, PIR control not started"
		fi
	else
		log "Warning: pir.py not found, PIR control not started"
	fi
	
	CURRENT_STATE="ON"
	log "MagicMirror startup complete"
	return 0
}

# Stop MagicMirror and PIR
stop_magicmirror() {
	log "Stopping MagicMirror..."
	
	# Stop PIR first (so it doesn't try to turn display back on)
	if [[ -n "$PIR_PID" ]] && kill -0 "$PIR_PID" 2>/dev/null; then
		log "Stopping PIR control (PID: $PIR_PID)"
		kill "$PIR_PID" 2>/dev/null || true
		sleep 1
		# Force kill if still running
		if kill -0 "$PIR_PID" 2>/dev/null; then
			kill -9 "$PIR_PID" 2>/dev/null || true
		fi
	fi
	PIR_PID=""
	
	# Stop MagicMirror
	if [[ -n "$MM_PID" ]] && kill -0 "$MM_PID" 2>/dev/null; then
		log "Stopping MagicMirror (PID: $MM_PID)"
		kill "$MM_PID" 2>/dev/null || true
		sleep 2
		# Force kill if still running
		if kill -0 "$MM_PID" 2>/dev/null; then
			log "Force killing MagicMirror (PID: $MM_PID)"
			kill -9 "$MM_PID" 2>/dev/null || true
		fi
	fi
	MM_PID=""
	
	# Aggressive cleanup: kill any remaining electron processes
	pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	pkill -9 -f "pir.py" 2>/dev/null || true
	
	# Turn display OFF
	if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
		/usr/bin/vcgencmd display_power 0 2>/dev/null || log "Warning: vcgencmd display_power failed"
	fi
	
	CURRENT_STATE="OFF"
	log "MagicMirror stopped"
}

# Check health of running processes and restart if needed
check_health() {
	# Only check health if we think we're ON
	if [[ "$CURRENT_STATE" != "ON" ]]; then
		return
	fi
	
	# Check MagicMirror
	if [[ -n "$MM_PID" ]] && ! kill -0 "$MM_PID" 2>/dev/null; then
		log "ERROR: MagicMirror crashed (PID $MM_PID no longer exists)"
		# Full restart
		stop_magicmirror
		sleep 5
		if start_magicmirror; then
			log "MagicMirror restarted successfully after crash"
		else
			log "ERROR: Failed to restart MagicMirror, will retry on next cycle"
		fi
		return
	fi
	
	# Check PIR (auto-restart if crashed)
	if [[ -n "$PIR_PID" ]] && ! kill -0 "$PIR_PID" 2>/dev/null; then
		log "Warning: PIR crashed (PID $PIR_PID no longer exists), restarting..."
		if [[ -f "${SCRIPT_DIR}/pir-control-display/pir.py" ]] && command -v python3 >/dev/null 2>&1; then
			python3 "${SCRIPT_DIR}/pir-control-display/pir.py" >> /tmp/pir.log 2>&1 &
			PIR_PID=$!
			log "PIR control restarted (PID: $PIR_PID)"
		else
			log "ERROR: Cannot restart PIR (script or python3 not found)"
			PIR_PID=""
		fi
	fi
}

# Main loop
main() {
	log "=== MagicMirror Scheduler Starting ==="
	log "Script: $0"
	log "Working directory: $(pwd)"
	log "User: $(whoami)"
	log "Display: ${DISPLAY:-not set}"
	
	# Load schedule
	load_schedule
	
	# Determine initial state based on schedule
	log "Determining initial state based on current time..."
	if should_be_running; then
		log "Current time is within schedule, starting MagicMirror..."
		start_magicmirror || log "Failed to start MagicMirror, will retry"
	else
		log "Current time is outside schedule, staying OFF"
		CURRENT_STATE="OFF"
		# Ensure display is OFF
		if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
			/usr/bin/vcgencmd display_power 0 2>/dev/null || true
		fi
	fi
	
	log "Entering main monitoring loop (checking every 30 seconds)..."
	
	# Main monitoring loop
	while true; do
		# Check if schedule says we should be running
		if should_be_running; then
			# Should be ON
			if [[ "$CURRENT_STATE" != "ON" ]]; then
				log "Schedule transition: OFF → ON"
				start_magicmirror || log "Failed to start, will retry on next cycle"
			else
				# Already running, check health
				check_health
			fi
		else
			# Should be OFF
			if [[ "$CURRENT_STATE" != "OFF" ]]; then
				log "Schedule transition: ON → OFF"
				stop_magicmirror
			fi
		fi
		
		# Sleep for 30 seconds
		sleep 30
	done
}

# Run main function
main
