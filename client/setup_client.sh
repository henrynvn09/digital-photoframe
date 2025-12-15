#!/bin/bash
# MagicMirror Client Setup Script for Raspberry Pi
# This script configures the Raspberry Pi to run MagicMirror in client-only mode
# with automatic scheduling and PIR motion sensor display control

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
MM_DIR="${HOME}/MagicMirror"
SERVER_IP="192.168.4.45"
SERVER_PORT="8036"

# Flags to track what was installed
INSTALLED_DEPS=false
INSTALLED_SYSTEMD=false

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

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
    print_header "Pre-flight Checks"
    
    local all_checks_passed=true
    
    # Check if running on Raspberry Pi
    if [[ ! -f /proc/cpuinfo ]] || ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        print_warning "This doesn't appear to be a Raspberry Pi"
        if ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    else
        print_success "Running on Raspberry Pi"
    fi
    
    # Check if running as pi user (or at least not root)
    if [[ "$EUID" -eq 0 ]]; then
        print_error "This script should NOT be run as root"
        print_info "Please run as regular user (e.g., 'pi'): ./setup_client.sh"
        exit 1
    else
        print_success "Running as user: $USER"
    fi
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo access for some operations"
        print_info "You may be prompted for your password"
        if ! sudo true; then
            print_error "Cannot obtain sudo access"
            exit 1
        fi
    fi
    print_success "Sudo access confirmed"
    
    # Check if MagicMirror directory exists
    if [[ ! -d "$MM_DIR" ]]; then
        print_error "MagicMirror directory not found: $MM_DIR"
        print_info "Please install MagicMirror first:"
        print_info "  bash -c \"\$(curl -sL https://raw.githubusercontent.com/sdetweil/MagicMirror_scripts/master/raspberry.sh)\""
        exit 1
    else
        print_success "MagicMirror found at: $MM_DIR"
    fi
    
    # Check for required npm scripts in package.json
    if [[ -f "$MM_DIR/package.json" ]]; then
        if grep -q "start:x11" "$MM_DIR/package.json"; then
            print_success "MagicMirror has X11 client support"
        else
            print_warning "MagicMirror may not have X11 client script"
            print_info "This is usually okay, fallback method will be used"
        fi
    fi
    
    # Check if repository is in expected location
    if [[ ! -f "$REPO_ROOT/AGENTS.md" ]]; then
        print_error "Cannot find repository root (looking for AGENTS.md)"
        print_info "Expected location: $REPO_ROOT"
        exit 1
    else
        print_success "Repository found at: $REPO_ROOT"
    fi
    
    # Check network connectivity to server
    print_info "Checking connectivity to MagicMirror server..."
    if check_command nc; then
        if timeout 3 nc -zv "$SERVER_IP" "$SERVER_PORT" 2>/dev/null; then
            print_success "Server reachable at ${SERVER_IP}:${SERVER_PORT}"
        else
            print_warning "Cannot reach server at ${SERVER_IP}:${SERVER_PORT}"
            print_info "Make sure your NAS is running and accessible"
            if ! ask_yes_no "Continue anyway?"; then
                exit 1
            fi
        fi
    else
        print_info "Skipping server connectivity check (nc not installed)"
    fi
    
    # Check for GPIO access (for PIR sensor)
    if [[ -d /sys/class/gpio ]]; then
        print_success "GPIO interface available"
    else
        print_warning "GPIO interface not found (PIR sensor may not work)"
    fi
    
    # Check display environment
    if [[ -n "${DISPLAY:-}" ]]; then
        print_success "Display environment set: $DISPLAY"
    else
        print_warning "DISPLAY environment variable not set"
        print_info "This is normal if running via SSH. Will be configured in cron/systemd."
    fi
    
    echo ""
}

# ============================================================================
# Install Dependencies
# ============================================================================

install_dependencies() {
    print_header "Installing Dependencies"
    
    print_info "Checking for required packages..."
    
    local packages_to_install=()
    
    # Check for Python3
    if ! check_command python3; then
        packages_to_install+=("python3")
    else
        print_success "python3 is installed"
    fi
    
    # Check for pip3
    if ! check_command pip3; then
        packages_to_install+=("python3-pip")
    else
        print_success "pip3 is installed"
    fi
    
    # Check for netcat
    if ! check_command nc; then
        packages_to_install+=("netcat-openbsd")
    else
        print_success "netcat is installed"
    fi
    
    # Check for git
    if ! check_command git; then
        packages_to_install+=("git")
    else
        print_success "git is installed"
    fi
    
    # Install missing packages
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        print_info "Need to install: ${packages_to_install[*]}"
        if ask_yes_no "Install these packages?"; then
            print_info "Updating package list..."
            sudo apt-get update -qq
            
            print_info "Installing packages..."
            sudo apt-get install -y "${packages_to_install[@]}"
            print_success "Packages installed"
            INSTALLED_DEPS=true
        else
            print_warning "Skipping package installation (some features may not work)"
        fi
    else
        print_success "All required packages are installed"
    fi
    
    # Check for Python gpiozero library
    print_info "Checking Python dependencies..."
    if python3 -c "import gpiozero" 2>/dev/null; then
        print_success "gpiozero is installed"
    else
        print_warning "gpiozero not found (required for PIR sensor)"
        if ask_yes_no "Install gpiozero via pip3?"; then
            pip3 install --user gpiozero
            print_success "gpiozero installed"
            INSTALLED_DEPS=true
        else
            print_warning "PIR sensor will not work without gpiozero"
        fi
    fi
    
    # Check GPIO group membership
    if groups "$USER" | grep -q gpio; then
        print_success "User $USER is in gpio group"
    else
        print_warning "User $USER is not in gpio group (needed for PIR sensor)"
        if ask_yes_no "Add $USER to gpio group?"; then
            sudo usermod -a -G gpio "$USER"
            print_success "User added to gpio group"
            print_warning "You must LOG OUT and LOG BACK IN for this to take effect!"
        fi
    fi
    
    echo ""
}

# ============================================================================
# Make Scripts Executable
# ============================================================================

setup_scripts() {
    print_header "Setting Up Scripts"
    
    local scripts=(
        "$SCRIPT_DIR/check_server.sh"
        "$SCRIPT_DIR/mm.sh"
        "$SCRIPT_DIR/turn_on_magic_mirror.sh"
        "$SCRIPT_DIR/turn_off_magic_mirror.sh"
        "$SCRIPT_DIR/pir-control-display/turn_on_display.sh"
        "$SCRIPT_DIR/pir-control-display/turn_off_display.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
            print_success "Made executable: $(basename "$script")"
        else
            print_warning "Script not found: $script"
        fi
    done
    
    echo ""
}

# ============================================================================
# Test Server Connectivity
# ============================================================================

test_server() {
    print_header "Testing Server Connectivity"
    
    print_info "Running connectivity test to ${SERVER_IP}:${SERVER_PORT}..."
    
    if [[ -x "$SCRIPT_DIR/check_server.sh" ]]; then
        if "$SCRIPT_DIR/check_server.sh" 3 2; then
            print_success "Server connectivity test passed!"
        else
            print_error "Cannot connect to MagicMirror server"
            print_info "Please ensure:"
            print_info "  1. Your NAS is powered on"
            print_info "  2. MagicMirror Docker container is running"
            print_info "  3. Network connection is active"
            print_info "  4. Server IP is correct: $SERVER_IP"
            
            if ! ask_yes_no "Continue anyway?"; then
                exit 1
            fi
        fi
    else
        print_warning "check_server.sh not found, skipping test"
    fi
    
    echo ""
}

# ============================================================================
# Choose Scheduling Method
# ============================================================================

choose_scheduling_method() {
    print_header "Configure Automatic Scheduling"
    
    cat << 'EOF'
MagicMirror will be configured with systemd timers for automatic scheduling.

Benefits:
  • Auto-restart on crash (no more blackouts!)
  • Better logging with journalctl
  • Modern service management
  • Service dependencies (PIR controlled properly)

Schedule:
  • Weekends: ON at 8:00 AM, OFF at 8:45 PM
  • Weekdays: ON at 4:00 PM, OFF at 8:45 PM

EOF
    
    if ask_yes_no "Enable automatic scheduling with systemd timers?"; then
        SCHEDULING_METHOD="systemd"
        print_success "Systemd scheduling will be configured"
    else
        SCHEDULING_METHOD="none"
        print_success "Skipping automatic scheduling (manual control only)"
        print_info "You can run setup again later to enable scheduling"
    fi
    
    echo ""
}

# ============================================================================
# Configure Systemd
# ============================================================================

configure_systemd() {
    print_header "Installing Systemd Services"
    
    if [[ ! -d "$SCRIPT_DIR/systemd" ]]; then
        print_error "Systemd directory not found: ${SCRIPT_DIR}/systemd"
        return 1
    fi
    
    # Copy service files
    print_info "Installing systemd service files..."
    
    local service_files=(
        "magicmirror-client.service"
        "magicmirror-pir.service"
        "magicmirror-on@.service"
        "magicmirror-off.service"
    )
    
    local timer_files=(
        "magicmirror-on@weekend.timer"
        "magicmirror-on@weekday.timer"
        "magicmirror-off.timer"
    )
    
    # Get current user's UID for XDG_RUNTIME_DIR
    local user_uid
    user_uid=$(id -u)
    
    for file in "${service_files[@]}" "${timer_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/systemd/$file" ]]; then
            # Replace placeholders with actual values
            sed -e "s|__USER__|${USER}|g" \
                -e "s|__UID__|${user_uid}|g" \
                -e "s|__INSTALL_DIR__|${SCRIPT_DIR}|g" \
                "$SCRIPT_DIR/systemd/$file" | sudo tee "/etc/systemd/system/$file" > /dev/null
            print_success "Installed: $file"
        else
            print_warning "File not found: $file"
        fi
    done
    
    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    # Enable and start timers
    print_info "Enabling and starting systemd timers..."
    sudo systemctl enable magicmirror-on@weekend.timer
    sudo systemctl enable magicmirror-on@weekday.timer
    sudo systemctl enable magicmirror-off.timer
    
    sudo systemctl start magicmirror-on@weekend.timer
    sudo systemctl start magicmirror-on@weekday.timer
    sudo systemctl start magicmirror-off.timer
    
    print_success "Systemd timers enabled and started"
    INSTALLED_SYSTEMD=true
    
    echo ""
}

# ============================================================================
# Test Installation
# ============================================================================

# ============================================================================
# Print Summary
# ============================================================================

print_summary() {
    print_header "Setup Complete!"
    
    print_success "MagicMirror client setup finished"
    echo ""
    
    if [[ "$INSTALLED_DEPS" == true ]]; then
        print_info "✓ Dependencies installed"
    fi
    
    if [[ "$INSTALLED_SYSTEMD" == true ]]; then
        print_info "✓ Systemd services installed and enabled"
        print_info "  - Weekends: ON at 8:00 AM, OFF at 8:45 PM"
        print_info "  - Weekdays: ON at 4:00 PM, OFF at 8:45 PM"
    fi
    
    if [[ "$SCHEDULING_METHOD" == "none" ]]; then
        print_info "✓ Manual control only (no automatic scheduling)"
        print_info "  - Start: ${SCRIPT_DIR}/turn_on_magic_mirror.sh"
        print_info "  - Stop: ${SCRIPT_DIR}/turn_off_magic_mirror.sh"
    fi
    
    echo ""
    print_header "Next Steps"
    
    if groups "$USER" | grep -q gpio; then
        : # User already in gpio group
    else
        print_warning "IMPORTANT: Log out and log back in for GPIO permissions to take effect"
    fi
    
    echo ""
    print_info "Manual Control Commands:"
    echo "  Start:  $SCRIPT_DIR/turn_on_magic_mirror.sh"
    echo "  Stop:   $SCRIPT_DIR/turn_off_magic_mirror.sh"
    echo ""
    
    if [[ "$INSTALLED_SYSTEMD" == true ]]; then
        print_info "Systemd Commands:"
        echo "  Status: systemctl status magicmirror-client.service"
        echo "  Logs:   journalctl -u magicmirror-client.service -n 50"
        echo "  Timers: systemctl list-timers magicmirror-*"
        echo ""
    fi
    
    print_info "Troubleshooting:"
    echo "  Server test:     $SCRIPT_DIR/check_server.sh"
    echo "  View logs:       tail -50 /tmp/magicmirror.log"
    echo "  PIR logs:        tail -50 /tmp/pir.log"
    echo "  Documentation:   $REPO_ROOT/AGENTS.md"
    echo ""
    
    if [[ "$SCHEDULING_METHOD" == "none" ]]; then
        print_success "Setup complete! Use manual control commands to start MagicMirror."
    else
        print_success "Setup complete! Your MagicMirror will start automatically on schedule."
    fi
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
║          MagicMirror Client Setup for Raspberry Pi          ║
║                                                              ║
║  This script will configure your Raspberry Pi to run        ║
║  MagicMirror in client-only mode with automatic scheduling  ║
║  and PIR motion sensor display control.                     ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    print_warning "This script will make changes to your system"
    print_info "It will:"
    print_info "  • Install required packages (with your permission)"
    print_info "  • Configure cron or systemd for automatic scheduling"
    print_info "  • Set up scripts for MagicMirror client control"
    echo ""
    
    if ! ask_yes_no "Continue with setup?" "y"; then
        print_info "Setup cancelled"
        exit 0
    fi
    
    # Run setup steps
    preflight_checks
    install_dependencies
    setup_scripts
    test_server
    
    # Ask user to choose scheduling method upfront
    choose_scheduling_method
    
    # Configure scheduling if selected
    if [[ "$SCHEDULING_METHOD" == "systemd" ]]; then
        configure_systemd
    else
        print_info "Skipping automatic scheduling (manual control only)"
        print_info "To start MagicMirror manually: ${SCRIPT_DIR}/turn_on_magic_mirror.sh"
        print_info "To stop MagicMirror manually: ${SCRIPT_DIR}/turn_off_magic_mirror.sh"
        echo ""
    fi
    
    print_summary
}

# Run main function
main "$@"
