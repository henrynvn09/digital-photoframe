#!/bin/bash
# MagicMirror Client Uninstall Script for Raspberry Pi
# This script removes MagicMirror client configuration including:
# - Systemd services and timers
# - Cron jobs
# - Running processes
# Note: This does NOT uninstall dependencies (Node.js, npm, etc.)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Flags to track what was removed
REMOVED_SYSTEMD=false
REMOVED_CRON=false
STOPPED_PROCESSES=false

# ============================================================================
# Utility Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    while true; do
        read -rp "$prompt" answer
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# ============================================================================
# Stop Running Processes
# ============================================================================

stop_processes() {
    print_header "Stopping Running Processes"
    
    local stopped_any=false
    local PID_FILE="/tmp/mm_pids.txt"
    local OLD_MM_PID_FILE="/tmp/mm.pid"
    local OLD_PIR_PID_FILE="/tmp/pir.pid"
    
    # Try to stop processes using PID file (new format)
    if [[ -f "${PID_FILE}" ]]; then
        print_info "Found PID file: ${PID_FILE}"
        
        # Parse PIDs from file
        local NPM_PID=""
        local ELECTRON_PID=""
        local PIR_PID=""
        
        while IFS=: read -r type pid; do
            case "${type}" in
                NPM) NPM_PID="${pid}" ;;
                ELECTRON) ELECTRON_PID="${pid}" ;;
                PIR) PIR_PID="${pid}" ;;
            esac
        done < "${PID_FILE}"
        
        # Stop PIR sensor first
        if [[ -n "${PIR_PID}" ]] && kill -0 "${PIR_PID}" 2>/dev/null; then
            print_info "Stopping PIR sensor (PID: ${PIR_PID})..."
            kill -9 "${PIR_PID}" 2>/dev/null || true
            print_success "PIR sensor stopped"
            stopped_any=true
        fi
        
        # Stop electron process
        if [[ -n "${ELECTRON_PID}" ]] && kill -0 "${ELECTRON_PID}" 2>/dev/null; then
            print_info "Stopping MagicMirror electron (PID: ${ELECTRON_PID})..."
            kill -9 "${ELECTRON_PID}" 2>/dev/null || true
            print_success "Electron process stopped"
            stopped_any=true
        fi
        
        # Stop npm parent process
        if [[ -n "${NPM_PID}" ]] && kill -0 "${NPM_PID}" 2>/dev/null; then
            print_info "Stopping npm parent (PID: ${NPM_PID})..."
            kill -9 "${NPM_PID}" 2>/dev/null || true
            print_success "npm process stopped"
            stopped_any=true
        fi
        
        # Remove PID file
        rm -f "${PID_FILE}"
        print_success "Removed PID file: ${PID_FILE}"
        
    # Handle old PID files (backward compatibility)
    elif [[ -f "${OLD_MM_PID_FILE}" ]] || [[ -f "${OLD_PIR_PID_FILE}" ]]; then
        print_info "Found old-format PID files"
        
        if [[ -f "${OLD_MM_PID_FILE}" ]]; then
            local OLD_MM_PID
            OLD_MM_PID=$(cat "${OLD_MM_PID_FILE}")
            if kill -0 "${OLD_MM_PID}" 2>/dev/null; then
                print_info "Stopping MagicMirror (PID: ${OLD_MM_PID})..."
                kill -9 "${OLD_MM_PID}" 2>/dev/null || true
                print_success "MagicMirror stopped"
                stopped_any=true
            fi
            rm -f "${OLD_MM_PID_FILE}"
        fi
        
        if [[ -f "${OLD_PIR_PID_FILE}" ]]; then
            local OLD_PIR_PID
            OLD_PIR_PID=$(cat "${OLD_PIR_PID_FILE}")
            if kill -0 "${OLD_PIR_PID}" 2>/dev/null; then
                print_info "Stopping PIR sensor (PID: ${OLD_PIR_PID})..."
                kill -9 "${OLD_PIR_PID}" 2>/dev/null || true
                print_success "PIR sensor stopped"
                stopped_any=true
            fi
            rm -f "${OLD_PIR_PID_FILE}"
        fi
    fi
    
    # Fallback: aggressive cleanup if no PID files found or processes still running
    if pgrep -f "electron.*js/electron.js" > /dev/null; then
        print_info "Stopping MagicMirror client processes (fallback)..."
        pkill -9 -f "electron.*js/electron.js" || true
        print_success "MagicMirror client stopped"
        stopped_any=true
    fi
    
    if pgrep -f "pir.py" > /dev/null; then
        print_info "Stopping PIR sensor script (fallback)..."
        pkill -9 -f "pir.py" || true
        print_success "PIR sensor script stopped"
        stopped_any=true
    fi
    
    # Remove lock file if it exists
    if [[ -d /tmp/mm_instance.lock ]]; then
        rmdir /tmp/mm_instance.lock 2>/dev/null || true
        print_success "Removed lock file"
        stopped_any=true
    fi
    
    if [[ "$stopped_any" == true ]]; then
        STOPPED_PROCESSES=true
        print_success "All MagicMirror processes stopped"
    else
        print_info "No running processes found"
    fi
    
    echo ""
}

# ============================================================================
# Remove Systemd Services
# ============================================================================

remove_systemd() {
    print_header "Removing Systemd Services"
    
    # Check if any systemd services are installed
    local systemd_files=(
        "magicmirror-client.service"
        "magicmirror-pir.service"
        "magicmirror-on@.service"
        "magicmirror-on@weekend.timer"
        "magicmirror-on@weekday.timer"
        "magicmirror-off.service"
        "magicmirror-off.timer"
    )
    
    local found_any=false
    for file in "${systemd_files[@]}"; do
        if [[ -f "/etc/systemd/system/$file" ]]; then
            found_any=true
            break
        fi
    done
    
    if [[ "$found_any" == false ]]; then
        print_info "No systemd services found"
        echo ""
        return
    fi
    
    print_warning "The following systemd services will be removed:"
    for file in "${systemd_files[@]}"; do
        if [[ -f "/etc/systemd/system/$file" ]]; then
            echo "  - $file"
        fi
    done
    echo ""
    
    if ! ask_yes_no "Remove systemd services?" "n"; then
        print_info "Skipping systemd removal"
        echo ""
        return
    fi
    
    # Stop and disable timers
    print_info "Stopping and disabling timers..."
    sudo systemctl stop magicmirror-on@weekend.timer 2>/dev/null || true
    sudo systemctl stop magicmirror-on@weekday.timer 2>/dev/null || true
    sudo systemctl stop magicmirror-off.timer 2>/dev/null || true
    
    sudo systemctl disable magicmirror-on@weekend.timer 2>/dev/null || true
    sudo systemctl disable magicmirror-on@weekday.timer 2>/dev/null || true
    sudo systemctl disable magicmirror-off.timer 2>/dev/null || true
    
    # Stop services if running
    print_info "Stopping services..."
    sudo systemctl stop magicmirror-client.service 2>/dev/null || true
    sudo systemctl stop magicmirror-pir.service 2>/dev/null || true
    
    # Remove service files
    print_info "Removing service files..."
    for file in "${systemd_files[@]}"; do
        if [[ -f "/etc/systemd/system/$file" ]]; then
            sudo rm -f "/etc/systemd/system/$file"
            print_success "Removed: $file"
        fi
    done
    
    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    print_success "Systemd services removed"
    REMOVED_SYSTEMD=true
    echo ""
}

# ============================================================================
# Remove Cron Jobs
# ============================================================================

remove_cron() {
    print_header "Removing Cron Jobs"
    
    # Check if any MagicMirror cron jobs exist
    if ! crontab -l 2>/dev/null | grep -q "magicmirror\|magic_mirror\|MagicMirror"; then
        print_info "No MagicMirror cron jobs found"
        echo ""
        return
    fi
    
    print_warning "The following cron jobs will be removed:"
    crontab -l 2>/dev/null | grep "magicmirror\|magic_mirror\|MagicMirror" || true
    echo ""
    
    if ! ask_yes_no "Remove cron jobs?" "n"; then
        print_info "Skipping cron removal"
        echo ""
        return
    fi
    
    # Backup existing crontab
    local backup_file="${HOME}/crontab_backup_uninstall_$(date +%Y%m%d_%H%M%S).txt"
    if crontab -l > "$backup_file" 2>/dev/null; then
        print_success "Backed up existing crontab to: $backup_file"
    fi
    
    # Remove MagicMirror cron jobs
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "magicmirror\|magic_mirror\|MagicMirror" > "$temp_cron" || true
    
    # Also remove environment variables set by setup script
    sed -i '/# MagicMirror Environment Variables/,/^$/d' "$temp_cron" 2>/dev/null || true
    
    crontab "$temp_cron"
    rm -f "$temp_cron"
    
    print_success "Cron jobs removed"
    REMOVED_CRON=true
    echo ""
}

# ============================================================================
# Clean Up Log Files
# ============================================================================

cleanup_logs() {
    print_header "Cleaning Up Log Files"
    
    local log_files=(
        "${HOME}/magicmirror_start.log"
        "${HOME}/magicmirror_stop.log"
        "/tmp/magicmirror.log"
        "/tmp/pir.log"
        "/tmp/mm_pids.txt"
        "/tmp/mm.pid"
        "/tmp/pir.pid"
    )
    
    local found_any=false
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            found_any=true
            break
        fi
    done
    
    if [[ "$found_any" == false ]]; then
        print_info "No log files found"
        echo ""
        return
    fi
    
    print_info "The following log files can be removed:"
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo "  - $log_file"
        fi
    done
    echo ""
    
    if ! ask_yes_no "Remove log files?" "n"; then
        print_info "Keeping log files"
        echo ""
        return
    fi
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            rm -f "$log_file"
            print_success "Removed: $log_file"
        fi
    done
    
    print_success "Log files removed"
    echo ""
}

# ============================================================================
# Print Summary
# ============================================================================

print_summary() {
    print_header "Uninstall Complete!"
    
    if [[ "$STOPPED_PROCESSES" == true ]]; then
        print_info "✓ Running processes stopped"
    fi
    
    if [[ "$REMOVED_SYSTEMD" == true ]]; then
        print_info "✓ Systemd services removed"
    fi
    
    if [[ "$REMOVED_CRON" == true ]]; then
        print_info "✓ Cron jobs removed"
    fi
    
    echo ""
    print_info "What was NOT removed:"
    echo "  • MagicMirror repository (${HOME}/MagicMirror)"
    echo "  • This configuration repository (${REPO_ROOT})"
    echo "  • Installed packages (Node.js, npm, python3-gpiozero, etc.)"
    echo "  • GPIO group membership"
    echo ""
    
    print_info "To completely remove MagicMirror:"
    echo "  1. Remove the MagicMirror directory: rm -rf ${HOME}/MagicMirror"
    echo "  2. Remove this config directory: rm -rf ${REPO_ROOT}"
    echo "  3. (Optional) Uninstall packages: sudo apt remove nodejs npm python3-gpiozero"
    echo ""
    
    print_info "To reinstall MagicMirror client:"
    echo "  Run: ${SCRIPT_DIR}/setup_client.sh"
    echo ""
    
    print_success "MagicMirror client configuration has been removed"
    echo ""
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    clear
    
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        MagicMirror Client Uninstall for Raspberry Pi        ║
║                                                              ║
║  This script will remove MagicMirror client configuration:  ║
║    • Stop running processes                                 ║
║    • Remove systemd services and timers                     ║
║    • Remove cron jobs                                       ║
║    • Clean up log files                                     ║
║                                                              ║
║  Note: This will NOT remove installed packages or the       ║
║        MagicMirror repository itself.                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    print_warning "This will remove your MagicMirror client configuration"
    echo ""
    
    if ! ask_yes_no "Continue with uninstall?" "n"; then
        print_info "Uninstall cancelled"
        exit 0
    fi
    
    # Run uninstall steps
    stop_processes
    remove_systemd
    remove_cron
    cleanup_logs
    print_summary
}

# Run main function
main "$@"
