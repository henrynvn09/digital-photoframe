#!/bin/bash
# Start Early Script - Interactive Early Start Manager
# Starts MagicMirror before scheduled ON time
#
# Usage:
#   ./start_early.sh
#
# Behavior:
#   - If before ON time: Prompts to start early until scheduled OFF time
#   - If inside schedule: Shows "no action needed" message and exits
#   - If override active: Prompts to cancel early start
#   - If past OFF time: Shows error with next schedule
#   - Requires confirmation (default YES on Enter)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
OVERRIDE_FILE="/tmp/force_on_override"

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

# Convert 24h time to 12h format with AM/PM
format_time_12h() {
	local time_24="$1"  # Format: HH:MM
	local hour="${time_24%%:*}"
	local minute="${time_24##*:}"
	
	hour=$((10#$hour))  # Remove leading zeros
	
	local period="AM"
	local hour_12=$hour
	
	if [[ $hour -eq 0 ]]; then
		hour_12=12
	elif [[ $hour -eq 12 ]]; then
		period="PM"
	elif [[ $hour -gt 12 ]]; then
		hour_12=$((hour - 12))
		period="PM"
	fi
	
	echo "${hour_12}:${minute} ${period}"
}

# Calculate time difference in hours and minutes
time_until() {
	local target_min="$1"
	local current_min="$2"
	
	local diff=$((target_min - current_min))
	
	if [[ $diff -lt 0 ]]; then
		echo "PASSED"
		return
	fi
	
	local hours=$((diff / 60))
	local minutes=$((diff % 60))
	
	if [[ $hours -gt 0 ]]; then
		echo "in ${hours}h ${minutes}m"
	else
		echo "in ${minutes}m"
	fi
}

# Calculate time since
time_since() {
	local past_min="$1"
	local current_min="$2"
	
	local diff=$((current_min - past_min))
	
	local hours=$((diff / 60))
	local minutes=$((diff % 60))
	
	if [[ $hours -gt 0 ]]; then
		echo "${hours}h ${minutes}m ago"
	else
		echo "${minutes}m ago"
	fi
}

# Get day name
get_day_name() {
	date +%A
}

# Check if inside scheduled hours
is_inside_schedule() {
	local hour minute day current_min on_min off_min
	
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)
	
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	# Get today's schedule
	local on_time off_time
	if [[ $day -ge 6 ]]; then
		on_time="${SATURDAY_SUNDAY%%-*}"
		off_time="${SATURDAY_SUNDAY##*-}"
	else
		on_time="${MONDAY_FRIDAY%%-*}"
		off_time="${MONDAY_FRIDAY##*-}"
	fi
	
	# Parse times
	local on_hour on_min_val off_hour off_min_val
	on_hour="${on_time%%:*}"
	on_min_val="${on_time##*:}"
	off_hour="${off_time%%:*}"
	off_min_val="${off_time##*:}"
	
	on_min=$(( 10#$on_hour * 60 + 10#$on_min_val ))
	off_min=$(( 10#$off_hour * 60 + 10#$off_min_val ))
	
	# Check if inside window
	if [[ $current_min -ge $on_min && $current_min -lt $off_min ]]; then
		return 0  # Inside schedule
	else
		return 1  # Outside schedule
	fi
}

# Check if past today's OFF time
is_past_off_time() {
	local hour minute day current_min off_hour off_min off_minutes
	
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)
	
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	# Determine today's OFF time
	local off_time
	if [[ $day -ge 6 ]]; then
		off_time="${SATURDAY_SUNDAY##*-}"
	else
		off_time="${MONDAY_FRIDAY##*-}"
	fi
	
	# Parse OFF time
	off_hour="${off_time%%:*}"
	off_min="${off_time##*:}"
	off_minutes=$(( 10#$off_hour * 60 + 10#$off_min ))
	
	if [[ $current_min -ge $off_minutes ]]; then
		return 0  # Past OFF time
	else
		return 1  # Not past OFF time
	fi
}

# Display current status section
show_status_section() {
	local override_active="$1"
	
	local hour minute day day_name
	hour=$(date +%H)
	minute=$(date +%M)
	day=$(date +%u)
	day_name=$(get_day_name)
	
	local time_12h
	time_12h=$(format_time_12h "$(printf '%02d:%02d' $((10#$hour)) $((10#$minute)))")
	
	log "═══════════════════════════════════════════════════"
	log "CURRENT STATUS"
	log "═══════════════════════════════════════════════════"
	log "• Current time: $(printf '%02d:%02d' $((10#$hour)) $((10#$minute))) ($time_12h) $day_name"
	
	if [[ "$override_active" == "true" ]]; then
		log "• Override: ACTIVE (early start mode)"
		log "• MagicMirror: ON (started early)"
		log "• Display: ON"
	else
		if is_inside_schedule; then
			log "• MagicMirror: Should be ON (inside scheduled hours)"
		else
			if is_past_off_time; then
				log "• MagicMirror: OFF (after scheduled hours)"
			else
				log "• MagicMirror: OFF (before scheduled ON time)"
			fi
		fi
	fi
}

# Display schedule section
show_schedule_section() {
	local day hour minute current_min
	day=$(date +%u)
	hour=$(date +%H)
	minute=$(date +%M)
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	local on_time off_time schedule_type
	if [[ $day -ge 6 ]]; then
		on_time="${SATURDAY_SUNDAY%%-*}"
		off_time="${SATURDAY_SUNDAY##*-}"
		schedule_type="Weekend"
	else
		on_time="${MONDAY_FRIDAY%%-*}"
		off_time="${MONDAY_FRIDAY##*-}"
		schedule_type="Weekday"
	fi
	
	local on_12h off_12h
	on_12h=$(format_time_12h "$on_time")
	off_12h=$(format_time_12h "$off_time")
	
	# Parse times to minutes
	local on_hour on_min_val off_hour off_min_val on_min off_min
	on_hour="${on_time%%:*}"
	on_min_val="${on_time##*:}"
	off_hour="${off_time%%:*}"
	off_min_val="${off_time##*:}"
	on_min=$(( 10#$on_hour * 60 + 10#$on_min_val ))
	off_min=$(( 10#$off_hour * 60 + 10#$off_min_val ))
	
	log ""
	log "═══════════════════════════════════════════════════"
	log "TODAY'S SCHEDULE ($schedule_type)"
	log "═══════════════════════════════════════════════════"
	
	# Show ON time with status
	if [[ $current_min -lt $on_min ]]; then
		local until
		until=$(time_until "$on_min" "$current_min")
		log "• Scheduled ON:  $on_time ($on_12h) - $until"
	else
		local since
		since=$(time_since "$on_min" "$current_min")
		log "• Scheduled ON:  $on_time ($on_12h) [PASSED $since]"
	fi
	
	# Show OFF time with status
	if [[ $current_min -lt $off_min ]]; then
		local until
		until=$(time_until "$off_min" "$current_min")
		log "• Scheduled OFF: $off_time ($off_12h) - $until"
	else
		local since
		since=$(time_since "$off_min" "$current_min")
		log "• Scheduled OFF: $off_time ($off_12h) [PASSED $since]"
	fi
	
	# Show status
	if [[ $current_min -ge $on_min && $current_min -lt $off_min ]]; then
		log "• Status: Inside schedule window"
	elif [[ $current_min -lt $on_min ]]; then
		log "• Status: Before schedule (early start available)"
	else
		log "• Status: After hours"
	fi
}

# Show "already in schedule" message and exit
show_already_in_schedule() {
	show_status_section "false"
	show_schedule_section
	
	log ""
	log "═══════════════════════════════════════════════════"
	log "ℹ️  NO ACTION NEEDED"
	log "═══════════════════════════════════════════════════"
	log "You are currently within scheduled hours."
	log "MagicMirror should already be running normally."
	log ""
	log "No early start needed. The system will continue running"
	log "until the scheduled OFF time."
}

# Show start early prompt
show_start_early_prompt() {
	show_status_section "false"
	show_schedule_section
	
	# Get OFF time for prompt
	local day off_time off_12h
	day=$(date +%u)
	if [[ $day -ge 6 ]]; then
		off_time="${SATURDAY_SUNDAY##*-}"
	else
		off_time="${MONDAY_FRIDAY##*-}"
	fi
	off_12h=$(format_time_12h "$off_time")
	
	# Calculate time until OFF
	local hour minute current_min off_min
	hour=$(date +%H)
	minute=$(date +%M)
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	local off_hour off_min_val
	off_hour="${off_time%%:*}"
	off_min_val="${off_time##*:}"
	off_min=$(( 10#$off_hour * 60 + 10#$off_min_val ))
	
	local duration
	duration=$(time_until "$off_min" "$current_min")
	
	log ""
	log "═══════════════════════════════════════════════════"
	log "PROPOSED ACTION"
	log "═══════════════════════════════════════════════════"
	log "If you confirm, the following will happen:"
	log "  1. Display turns ON immediately"
	log "  2. MagicMirror starts within 30 seconds"
	log "  3. Stays ON until $off_time ($off_12h) - $duration"
	log "  4. After $off_time, returns to normal schedule"
	log ""
	
	if ! confirm "Start MagicMirror early and run until $off_time ($off_12h)?"; then
		log "Operation cancelled by user"
		exit 0
	fi
	
	# Create override
	touch "$OVERRIDE_FILE"
	
	# Turn on display immediately
	if command -v /usr/bin/vcgencmd >/dev/null 2>&1; then
		/usr/bin/vcgencmd display_power 1 2>/dev/null || log "Warning: Could not turn on display"
	fi
	
	log "✓ Early start activated"
	log "  Display turned on immediately"
	log "  MagicMirror will start within 30 seconds"
	log "  Will stay ON until $off_time ($off_12h)"
}

# Show remove override prompt
show_remove_override_prompt() {
	show_status_section "true"
	show_schedule_section
	
	local day hour minute current_min
	day=$(date +%u)
	hour=$(date +%H)
	minute=$(date +%M)
	current_min=$(( 10#$hour * 60 + 10#$minute ))
	
	# Get schedule times
	local on_time off_time
	if [[ $day -ge 6 ]]; then
		on_time="${SATURDAY_SUNDAY%%-*}"
		off_time="${SATURDAY_SUNDAY##*-}"
	else
		on_time="${MONDAY_FRIDAY%%-*}"
		off_time="${MONDAY_FRIDAY##*-}"
	fi
	
	local on_hour on_min_val off_hour off_min_val on_min off_min
	on_hour="${on_time%%:*}"
	on_min_val="${on_time##*:}"
	off_hour="${off_time%%:*}"
	off_min_val="${off_time##*:}"
	on_min=$(( 10#$on_hour * 60 + 10#$on_min_val ))
	off_min=$(( 10#$off_hour * 60 + 10#$off_min_val ))
	
	local on_12h off_12h
	on_12h=$(format_time_12h "$on_time")
	off_12h=$(format_time_12h "$off_time")
	
	log ""
	log "═══════════════════════════════════════════════════"
	log "PROPOSED ACTION"
	log "═══════════════════════════════════════════════════"
	log "If you confirm, the following will happen:"
	log "  1. Early start override removed"
	log "  2. Returns to normal schedule"
	
	if [[ $current_min -ge $on_min && $current_min -lt $off_min ]]; then
		# Inside schedule
		log "  3. Since current time is INSIDE schedule ($on_time-$off_time):"
		log "     → MagicMirror will STAY ON (normal schedule)"
		log "     → No immediate change"
		log "     → Will turn OFF at $off_time ($off_12h) as normal"
		log ""
		
		if ! confirm "Cancel early start and return to normal schedule (no change)?"; then
			log "Operation cancelled by user"
			exit 0
		fi
	else
		# Outside schedule
		log "  3. Since current time is BEFORE ON time ($on_time):"
		log "     → MagicMirror will STOP within 30 seconds"
		log "     → Display will turn OFF"
		log "     → Will restart automatically at $on_time ($on_12h)"
		log ""
		
		if ! confirm "Cancel early start and return to normal schedule (will turn OFF now)?"; then
			log "Operation cancelled by user"
			exit 0
		fi
	fi
	
	# Remove override
	rm -f "$OVERRIDE_FILE"
	log "✓ Early start cancelled"
	log "  Override removed"
	log "  Changes take effect within 30 seconds"
}

# Show error for past OFF time
show_past_off_time_error() {
	show_status_section "false"
	show_schedule_section
	
	local day
	day=$(date +%u)
	
	# Get off time
	local off_time
	if [[ $day -ge 6 ]]; then
		off_time="${SATURDAY_SUNDAY##*-}"
	else
		off_time="${MONDAY_FRIDAY##*-}"
	fi
	
	# Calculate next ON time
	local next_day next_on_time next_on_12h
	if [[ $day -ge 6 ]]; then
		if [[ $day -eq 7 ]]; then
			next_day="Monday"
			next_on_time="${MONDAY_FRIDAY%%-*}"
		else
			next_day="Sunday"
			next_on_time="${SATURDAY_SUNDAY%%-*}"
		fi
	else
		if [[ $day -eq 5 ]]; then
			next_day="Saturday"
			next_on_time="${SATURDAY_SUNDAY%%-*}"
		else
			next_day="tomorrow"
			next_on_time="${MONDAY_FRIDAY%%-*}"
		fi
	fi
	next_on_12h=$(format_time_12h "$next_on_time")
	
	log ""
	log "═══════════════════════════════════════════════════"
	log "❌ ERROR: CANNOT START EARLY"
	log "═══════════════════════════════════════════════════"
	log "Current time is past today's scheduled OFF time ($off_time)."
	log ""
	log "Early start is only available before the scheduled ON time."
	log "Starting now would run until tomorrow's OFF time (~23 hours)."
	log ""
	log "═══════════════════════════════════════════════════"
	log "NEXT SCHEDULED OPERATION"
	log "═══════════════════════════════════════════════════"
	log "• Next ON: $next_day at $next_on_time ($next_on_12h)"
	log ""
	log "MagicMirror will start automatically at that time."
	log ""
	log "For immediate control (advanced):"
	log "  sudo systemctl start digitalframe.service   (start scheduler now)"
	log "  sudo systemctl stop digitalframe.service    (stop everything)"
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
	
	# Check if override already active
	if [[ -f "$OVERRIDE_FILE" ]]; then
		show_remove_override_prompt
		exit 0
	fi
	
	# Check if inside schedule (no action needed)
	if is_inside_schedule; then
		show_already_in_schedule
		exit 0
	fi
	
	# Check if past OFF time (error)
	if is_past_off_time; then
		show_past_off_time_error
		exit 1
	fi
	
	# Show start early prompt (before ON time)
	show_start_early_prompt
}

main
