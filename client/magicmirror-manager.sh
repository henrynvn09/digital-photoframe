#!/bin/bash
# MagicMirror Schedule Manager
# Runs continuously, starts/stops MagicMirror based on schedule
# This script is managed by systemd (digitalframe.service)

# Error handling: -u (undefined vars) and -o pipefail, but NOT -e (exit on error)
# We want the loop to continue even if individual commands fail
set -uo pipefail

# Error trap for debugging
trap 'error_log "Command failed at line $LINENO: $BASH_COMMAND"' ERR

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

# Debug flag (loaded from config, defaults to false)
DEBUG=${DEBUG:-false}

# Logging functions with levels
log() { 
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

debug_log() {
	if [[ "$DEBUG" == "true" ]]; then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
	fi
}

error_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"
}

# Load schedule from config file
load_schedule() {
	debug_log "=== load_schedule() called ==="
	debug_log "Config file path: $SCHEDULE_CONF"
	
	# Set defaults first
	WEEKEND_ON_HOUR=$DEFAULT_WEEKEND_ON_HOUR
	WEEKEND_ON_MIN=$DEFAULT_WEEKEND_ON_MIN
	WEEKDAY_ON_HOUR=$DEFAULT_WEEKDAY_ON_HOUR
	WEEKDAY_ON_MIN=$DEFAULT_WEEKDAY_ON_MIN
	OFF_HOUR=$DEFAULT_OFF_HOUR
	OFF_MIN=$DEFAULT_OFF_MIN
	
	# Try to load from file
	if [[ -f "$SCHEDULE_CONF" ]]; then
		debug_log "Config file found, attempting to load..."
		# Source the file in a subshell to avoid polluting our environment
		# shellcheck disable=SC1090
		source "$SCHEDULE_CONF" || {
			error_log "Failed to parse $SCHEDULE_CONF, using defaults"
			return
		}
		debug_log "Config file loaded successfully"
		
		# Validate values (hours: 0-23, minutes: 0-59)
		if [[ $WEEKEND_ON_HOUR -lt 0 || $WEEKEND_ON_HOUR -gt 23 ]]; then
			error_log "Invalid WEEKEND_ON_HOUR=$WEEKEND_ON_HOUR, using default"
			WEEKEND_ON_HOUR=$DEFAULT_WEEKEND_ON_HOUR
		fi
		debug_log "Validated WEEKEND_ON_HOUR=$WEEKEND_ON_HOUR"
		
		if [[ $WEEKEND_ON_MIN -lt 0 || $WEEKEND_ON_MIN -gt 59 ]]; then
			error_log "Invalid WEEKEND_ON_MIN=$WEEKEND_ON_MIN, using default"
			WEEKEND_ON_MIN=$DEFAULT_WEEKEND_ON_MIN
		fi
		debug_log "Validated WEEKEND_ON_MIN=$WEEKEND_ON_MIN"
		
		if [[ $WEEKDAY_ON_HOUR -lt 0 || $WEEKDAY_ON_HOUR -gt 23 ]]; then
			error_log "Invalid WEEKDAY_ON_HOUR=$WEEKDAY_ON_HOUR, using default"
			WEEKDAY_ON_HOUR=$DEFAULT_WEEKDAY_ON_HOUR
		fi
		debug_log "Validated WEEKDAY_ON_HOUR=$WEEKDAY_ON_HOUR"
		
		if [[ $WEEKDAY_ON_MIN -lt 0 || $WEEKDAY_ON_MIN -gt 59 ]]; then
			error_log "Invalid WEEKDAY_ON_MIN=$WEEKDAY_ON_MIN, using default"
			WEEKDAY_ON_MIN=$DEFAULT_WEEKDAY_ON_MIN
		fi
		debug_log "Validated WEEKDAY_ON_MIN=$WEEKDAY_ON_MIN"
		
		if [[ $OFF_HOUR -lt 0 || $OFF_HOUR -gt 23 ]]; then
			error_log "Invalid OFF_HOUR=$OFF_HOUR, using default"
			OFF_HOUR=$DEFAULT_OFF_HOUR
		fi
		debug_log "Validated OFF_HOUR=$OFF_HOUR"
		
		if [[ $OFF_MIN -lt 0 || $OFF_MIN -gt 59 ]]; then
			error_log "Invalid OFF_MIN=$OFF_MIN, using default"
			OFF_MIN=$DEFAULT_OFF_MIN
		fi
		debug_log "Validated OFF_MIN=$OFF_MIN"
	else
		error_log "Schedule file not found: $SCHEDULE_CONF, using defaults"
	fi
	
	log "Schedule loaded: Weekend ON=${WEEKEND_ON_HOUR}:$(printf '%02d' $WEEKEND_ON_MIN), Weekday ON=${WEEKDAY_ON_HOUR}:$(printf '%02d' $WEEKDAY_ON_MIN), OFF=${OFF_HOUR}:$(printf '%02d' $OFF_MIN)"
	debug_log "DEBUG mode: $DEBUG"
	debug_log "=== load_schedule() completed ==="
}

# Check if MagicMirror should be running based on schedule
# Returns 0 (true) if should be ON, 1 (false) if should be OFF
should_be_running() {
	local hour minute day current_min on_min off_min day_name
	
	debug_log ">>> should_be_running() called"
	
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)  # 1=Mon, 2=Tue, ... 6=Sat, 7=Sun
	day_name=$(date +%A)
	
	debug_log "Current time: hour=$hour, minute=$minute, day=$day ($day_name)"
	
	# Convert to minutes since midnight (force base-10 to avoid octal issues)
	current_min=$((10#$hour * 60 + 10#$minute))
	off_min=$((OFF_HOUR * 60 + OFF_MIN))
	
	debug_log "Minutes since midnight: current=$current_min, off=$off_min"
	
	# Determine ON time based on day
	if [[ $day -ge 6 ]]; then
		# Weekend (Sat=6, Sun=7)
		on_min=$((WEEKEND_ON_HOUR * 60 + WEEKEND_ON_MIN))
		debug_log "Day type: WEEKEND, on_min=$on_min (from ${WEEKEND_ON_HOUR}:$(printf '%02d' $WEEKEND_ON_MIN))"
	else
		# Weekday (Mon=1 through Fri=5)
		on_min=$((WEEKDAY_ON_HOUR * 60 + WEEKDAY_ON_MIN))
		debug_log "Day type: WEEKDAY, on_min=$on_min (from ${WEEKDAY_ON_HOUR}:$(printf '%02d' $WEEKDAY_ON_MIN))"
	fi
	
	# Check if current time is within ON window
	debug_log "Checking: $current_min >= $on_min && $current_min < $off_min"
	if [[ $current_min -ge $on_min && $current_min -lt $off_min ]]; then
		debug_log "Result: TRUE (should be ON)"
		debug_log "<<< should_be_running() returning 0"
		return 0  # Should be ON
	else
		debug_log "Result: FALSE (should be OFF)"
		debug_log "Reason: current_min=$current_min is outside window [$on_min, $off_min)"
		debug_log "<<< should_be_running() returning 1"
		return 1  # Should be OFF
	fi
}

# Start MagicMirror and PIR
start_magicmirror() {
	debug_log ">>> start_magicmirror() called"
	log "Starting MagicMirror..."
	
	# Turn display ON
	if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
		debug_log "Attempting to turn display ON..."
		local display_result
		display_result=$(/usr/bin/vcgencmd display_power 1 2>&1) || error_log "vcgencmd display_power failed"
		debug_log "vcgencmd result: $display_result"
	fi
	
	# Check server connectivity
	if [[ -f "${SCRIPT_DIR}/check_server.sh" ]]; then
		debug_log "Checking server connectivity: ${SERVER_IP}:${SERVER_PORT}"
		if ! "${SCRIPT_DIR}/check_server.sh" 10 5; then
			error_log "Server not reachable at ${SERVER_IP}:${SERVER_PORT}, will retry later"
			debug_log "<<< start_magicmirror() failed (server unreachable)"
			return 1
		fi
		debug_log "Server connectivity check passed"
	else
		debug_log "Warning: check_server.sh not found, skipping connectivity check"
	fi
	
	# Start MagicMirror
	if [[ ! -d "$MM_DIR" ]]; then
		error_log "MagicMirror directory not found: $MM_DIR"
		debug_log "<<< start_magicmirror() failed (MM_DIR not found)"
		return 1
	fi
	
	debug_log "Changing to MagicMirror directory: $MM_DIR"
	cd "$MM_DIR" || return 1
	
	export clientonly=1
	export config="{\"address\":\"${SERVER_IP}\",\"port\":${SERVER_PORT}}"
	export DISPLAY="${DISPLAY:-:0}"
	
	debug_log "Environment: clientonly=1, DISPLAY=$DISPLAY"
	debug_log "Config: address=${SERVER_IP}, port=${SERVER_PORT}"
	
	# Start in background, redirect output to log
	debug_log "Executing: npm run start:x11"
	npm run start:x11 >> /tmp/magicmirror.log 2>&1 &
	MM_PID=$!
	
	log "MagicMirror started (PID: $MM_PID), waiting for initialization..."
	debug_log "npm process PID: $MM_PID"
	
	# Wait for electron to spawn
	debug_log "Waiting 3 seconds for electron to initialize..."
	sleep 3
	
	# Verify MagicMirror is still running
	debug_log "Verifying MagicMirror process is still alive..."
	if ! kill -0 "$MM_PID" 2>/dev/null; then
		error_log "MagicMirror process died immediately after start"
		MM_PID=""
		debug_log "<<< start_magicmirror() failed (process died)"
		return 1
	fi
	debug_log "MagicMirror process verified alive"
	
	# Start PIR controller
	if [[ -f "${SCRIPT_DIR}/pir-control-display/pir.py" ]]; then
		if command -v python3 >/dev/null 2>&1; then
			debug_log "Starting PIR control script..."
			python3 "${SCRIPT_DIR}/pir-control-display/pir.py" >> /tmp/pir.log 2>&1 &
			PIR_PID=$!
			log "PIR control started (PID: $PIR_PID)"
			debug_log "PIR process PID: $PIR_PID"
		else
			debug_log "Warning: python3 not found, PIR control not started"
		fi
	else
		debug_log "Warning: pir.py not found at ${SCRIPT_DIR}/pir-control-display/pir.py"
	fi
	
	CURRENT_STATE="ON"
	log "MagicMirror startup complete"
	debug_log "<<< start_magicmirror() completed successfully"
	return 0
}

# Stop MagicMirror and PIR
stop_magicmirror() {
	debug_log ">>> stop_magicmirror() called"
	log "Stopping MagicMirror..."
	
	# Stop PIR first (so it doesn't try to turn display back on)
	if [[ -n "$PIR_PID" ]] && kill -0 "$PIR_PID" 2>/dev/null; then
		log "Stopping PIR control (PID: $PIR_PID)"
		debug_log "Sending TERM signal to PIR process $PIR_PID"
		kill "$PIR_PID" 2>/dev/null || true
		sleep 1
		# Force kill if still running
		if kill -0 "$PIR_PID" 2>/dev/null; then
			debug_log "PIR still running, sending KILL signal"
			kill -9 "$PIR_PID" 2>/dev/null || true
		fi
		debug_log "PIR process stopped"
	else
		debug_log "PIR_PID empty or process not running"
	fi
	PIR_PID=""
	
	# Stop MagicMirror
	if [[ -n "$MM_PID" ]] && kill -0 "$MM_PID" 2>/dev/null; then
		log "Stopping MagicMirror (PID: $MM_PID)"
		debug_log "Sending TERM signal to MagicMirror process $MM_PID"
		kill "$MM_PID" 2>/dev/null || true
		sleep 2
		# Force kill if still running
		if kill -0 "$MM_PID" 2>/dev/null; then
			log "Force killing MagicMirror (PID: $MM_PID)"
			debug_log "Sending KILL signal to MagicMirror process $MM_PID"
			kill -9 "$MM_PID" 2>/dev/null || true
		fi
		debug_log "MagicMirror process stopped"
	else
		debug_log "MM_PID empty or process not running"
	fi
	MM_PID=""
	
	# Aggressive cleanup: kill any remaining electron processes
	debug_log "Performing aggressive cleanup of remaining processes"
	pkill -9 -f "electron.*js/electron.js" 2>/dev/null || true
	pkill -9 -f "pir.py" 2>/dev/null || true
	debug_log "Process cleanup completed"
	
	# Turn display OFF
	if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
		debug_log "Attempting to turn display OFF..."
		local display_result
		display_result=$(/usr/bin/vcgencmd display_power 0 2>&1) || error_log "vcgencmd display_power failed"
		debug_log "vcgencmd result: $display_result"
	fi
	
	CURRENT_STATE="OFF"
	log "MagicMirror stopped"
	debug_log "<<< stop_magicmirror() completed"
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
	debug_log "Loop will check schedule and manage state transitions"
	
	# Main monitoring loop with iteration counter
	local iteration=0
	while true; do
		iteration=$((iteration + 1))
		debug_log "============================================"
		debug_log "Loop iteration #$iteration starting at $(date '+%H:%M:%S')"
		debug_log "Current state: $CURRENT_STATE"
		debug_log "============================================"
		
		# Check if schedule says we should be running
		debug_log "Calling should_be_running()..."
		if should_be_running; then
			# Should be ON
			debug_log "should_be_running returned TRUE"
			if [[ "$CURRENT_STATE" != "ON" ]]; then
				log "Schedule transition: OFF → ON"
				debug_log "State mismatch detected, calling start_magicmirror()..."
				start_magicmirror || error_log "Failed to start, will retry on next cycle"
			else
				debug_log "Already ON, calling check_health()..."
				# Already running, check health
				check_health
			fi
		else
			# Should be OFF
			debug_log "should_be_running returned FALSE"
			if [[ "$CURRENT_STATE" != "OFF" ]]; then
				log "Schedule transition: ON → OFF"
				debug_log "State mismatch detected, calling stop_magicmirror()..."
				stop_magicmirror
			else
				debug_log "Already OFF, no action needed"
			fi
		fi
		
		debug_log "Loop iteration #$iteration completed"
		debug_log "Sleeping for 30 seconds..."
		# Sleep for 30 seconds
		sleep 30
	done
}

# Run main function
main
