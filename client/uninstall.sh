#!/bin/bash
# MagicMirror Client Uninstall Script for Raspberry Pi
# This script removes MagicMirror client configuration including:
# - Systemd service
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
# Remove Systemd Service
# ============================================================================

remove_systemd() {
    print_header "Removing Systemd Service"
    
    # Check for new service name (preferred) or old service name
    local has_new_service=false
    local has_old_service=false
    
    if [[ -f "/etc/systemd/system/digitalframe.service" ]]; then
        has_new_service=true
    fi
    
    if [[ -f "/etc/systemd/system/magicmirror.service" ]]; then
        has_old_service=true
    fi
    
    if [[ "$has_new_service" == false ]] && [[ "$has_old_service" == false ]]; then
        print_info "No systemd service found"
        echo ""
        return
    fi
    
    print_warning "The following systemd service(s) will be removed:"
    if [[ "$has_new_service" == true ]]; then
        echo "  - digitalframe.service"
    fi
    if [[ "$has_old_service" == true ]]; then
        echo "  - magicmirror.service (old)"
    fi
    echo ""
    
    if ! ask_yes_no "Remove systemd service?" "n"; then
        print_info "Skipping systemd removal"
        echo ""
        return
    fi
    
    # Remove new service if exists
    if [[ "$has_new_service" == true ]]; then
        print_info "Stopping digitalframe service..."
        sudo systemctl stop digitalframe.service 2>/dev/null || true
        
        print_info "Disabling digitalframe service..."
        sudo systemctl disable digitalframe.service 2>/dev/null || true
        
        print_info "Removing digitalframe service file..."
        sudo rm -f "/etc/systemd/system/digitalframe.service"
        print_success "Removed: digitalframe.service"
    fi
    
    # Remove old service if exists (backward compatibility)
    if [[ "$has_old_service" == true ]]; then
        print_info "Stopping old magicmirror service..."
        sudo systemctl stop magicmirror.service 2>/dev/null || true
        
        print_info "Disabling old magicmirror service..."
        sudo systemctl disable magicmirror.service 2>/dev/null || true
        
        print_info "Removing old magicmirror service file..."
        sudo rm -f "/etc/systemd/system/magicmirror.service"
        print_success "Removed: magicmirror.service (old)"
    fi
    
    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    print_success "Systemd service(s) removed"
    REMOVED_SYSTEMD=true
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
        print_info "No legacy log files found"
        echo ""
        
        # Note about journald logs
        print_info "System logs are managed by journald:"
        echo "  View logs: journalctl -u digitalframe.service"
        echo "  Clean logs: sudo journalctl --vacuum-size=8M"
        echo ""
        return
    fi
    
    print_info "The following legacy log files can be removed:"
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo "  - $log_file"
        fi
    done
    echo ""
    
    print_info "Note: Current versions use journald for logging (not /tmp files)"
    echo ""
    
    if ! ask_yes_no "Remove legacy log files?" "n"; then
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
    
    print_success "Legacy log files removed"
    
    # Show journald logs info
    echo ""
    print_info "To clean journald logs:"
    echo "  sudo journalctl --vacuum-time=1d"
    echo "  sudo journalctl --vacuum-size=8M"
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
║    • Remove systemd service                                 ║
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
    cleanup_logs
    print_summary
}

# Run main function
main "$@"
