#!/bin/bash
# Interactive Force ON/OFF Toggle Script
# Manages /tmp/digital_photoframe_force_on_override flag to control MagicMirror state
#
# Usage:
#   ./force_on_now.sh
#
# Behavior:
#   - If override is inactive: Prompts to force ON until scheduled OFF time
#   - If override is active: Prompts to remove override and return to normal schedule
#   - Requires confirmation (default YES on Enter)
#   - Validates time (rejects if past today's OFF time)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
OVERRIDE_FILE="/tmp/digital_photoframe_force_on_override"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Load configuration
load_config() {
	if [[ ! -f "$CONFIG_FILE" ]]; then
		log "ERROR: Config file not found: $CONFIG_FILE"
		exit 1
	fi
	
	# shellcheck disable=SC1090
	source "$CONFIG_FILE"
	
	# Validate required variables
	if [[ -z "${MONDAY_FRIDAY:-}" ]] || [[ -z "${SATURDAY_SUNDAY:-}" ]]; then
		log "ERROR: Schedule not configured in $CONFIG_FILE"
		log "       Expected: MONDAY_FRIDAY=HH:MM-HH:MM"
		log "       Expected: SATURDAY_SUNDAY=HH:MM-HH:MM"
		exit 1
	fi
}

# Parse time from schedule string (e.g., "16:00-20:45" -> extract 20:45)
get_off_time() {
	local schedule="$1"
	local off_time="${schedule##*-}"  # Extract after dash
	echo "$off_time"
}

# Check if current time is past today's scheduled OFF time
is_past_off_time() {
	local hour minute day current_min off_hour off_min off_minutes
	
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)  # 1=Mon through 7=Sun
	
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	# Determine today's OFF time based on day type
	local off_time
	if [[ $day -ge 6 ]]; then
		# Weekend
		off_time=$(get_off_time "$SATURDAY_SUNDAY")
	else
		# Weekday
		off_time=$(get_off_time "$MONDAY_FRIDAY")
	fi
	
	# Parse OFF time (HH:MM)
	off_hour="${off_time%%:*}"
	off_min="${off_time##*:}"
	off_minutes=$(( 10#$off_hour * 60 + 10#$off_min ))
	
	if [[ $current_min -ge $off_minutes ]]; then
		# Past OFF time - show detailed error
		log "ERROR: Current time ($(date +%H:%M)) is past today's scheduled OFF time ($off_time)"
		log ""
		log "Cannot force ON after scheduled OFF time."
		
		# Calculate next ON time for helpful message
		local next_day next_on_time
		if [[ $day -ge 6 ]]; then
			# Currently weekend, check if Sunday
			if [[ $day -eq 7 ]]; then
				next_day="Monday"
				next_on_time="${MONDAY_FRIDAY%%-*}"
			else
				next_day="Sunday"
				next_on_time="${SATURDAY_SUNDAY%%-*}"
			fi
		else
			# Currently weekday
			if [[ $day -eq 5 ]]; then
				next_day="Saturday"
				next_on_time="${SATURDAY_SUNDAY%%-*}"
			else
				next_day="tomorrow"
				next_on_time="${MONDAY_FRIDAY%%-*}"
			fi
		fi
		
		log "Next scheduled ON time: $next_day at $next_on_time"
		log "MagicMirror will start automatically at that time."
		return 0  # True - is past OFF time
	fi
	
	return 1  # False - not past OFF time
}

# Prompt user for confirmation (default YES on Enter)
confirm() {
	local prompt="$1"
	local response
	
	read -r -p "$prompt [Y/n]: " response
	response=${response,,}  # Convert to lowercase
	
	# Default to YES if empty (just Enter pressed)
	if [[ -z "$response" ]] || [[ "$response" == "y" ]] || [[ "$response" == "yes" ]]; then
		return 0  # Confirmed
	else
		return 1  # Cancelled
	fi
}

# Main logic
main() {
	load_config
	
	# Check current state
	if [[ -f "$OVERRIDE_FILE" ]]; then
		# Override is active - offer to remove
		echo ""
		log "Override is currently ACTIVE"
		log "MagicMirror is forced ON until scheduled OFF time"
		echo ""
		
		if ! confirm "Do you want to REMOVE the override and return to normal schedule?"; then
			log "Operation cancelled by user"
			exit 0
		fi
		
		# Remove override
		rm -f "$OVERRIDE_FILE"
		log "✓ Override removed"
		log "  MagicMirror will follow normal schedule"
		log "  Changes take effect within 30 seconds"
		
	else
		# No override - offer to force ON
		echo ""
		log "No override currently active"
		log "MagicMirror is following normal schedule"
		echo ""
		
		# Validate time before prompting
		if is_past_off_time; then
			exit 1
		fi
		
		if ! confirm "Do you want to FORCE ON now and keep it on until scheduled OFF time?"; then
			log "Operation cancelled by user"
			exit 0
		fi
		
		# Create override
		touch "$OVERRIDE_FILE"
		
		# Turn on display immediately
		if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
			/usr/bin/vcgencmd display_power 1 2>/dev/null || log "Warning: Could not turn on display"
		fi
		
		log "✓ Override activated"
		log "  Display turned on immediately"
		log "  MagicMirror will start within 30 seconds"
		log "  Will stay ON until scheduled OFF time"
	fi
}

main
