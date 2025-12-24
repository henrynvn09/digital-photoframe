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

# These will be set by configure_schedule() function
SERVER_IP=""
SERVER_PORT=""

# Flags to track what was installed
INSTALLED_DEPS=false
INSTALLED_SYSTEMD=false
CONFIGURED_JOURNALD=false

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
    
    # Use defaults if not yet configured
    local test_ip="${SERVER_IP:-192.168.4.45}"
    local test_port="${SERVER_PORT:-8036}"
    
    print_info "Running connectivity test to ${test_ip}:${test_port}..."
    print_info "(You can customize server settings in the next step)"
    echo ""
    
    if [[ -x "$SCRIPT_DIR/check_server.sh" ]]; then
        # Temporarily set for check_server.sh
        SERVER_IP="$test_ip" SERVER_PORT="$test_port" "$SCRIPT_DIR/check_server.sh" 3 2
        local result=$?
        
        if [[ $result -eq 0 ]]; then
            print_success "Server connectivity test passed!"
        else
            print_error "Cannot connect to MagicMirror server at ${test_ip}:${test_port}"
            print_info "Please ensure:"
            print_info "  1. Your NAS is powered on"
            print_info "  2. MagicMirror Docker container is running"
            print_info "  3. Network connection is active"
            print_info "  4. Server IP is correct (default: ${test_ip})"
            echo ""
            print_info "You can specify a different server IP in the next configuration step"
            
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
MagicMirror will be configured with a unified systemd service for automatic scheduling.

Benefits:
  • Auto-restart on crash (no more blackouts!)
  • Schedule-aware: correct state on reboot
  • Better logging with journalctl
  • Modern service management
  • Automatic display power control

EOF
    
    if ask_yes_no "Enable automatic scheduling with systemd?"; then
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
# Configure Schedule
# ============================================================================

configure_schedule() {
    print_header "Configure Display Settings"
    
    # Ask for setup mode
    echo ""
    print_info "Choose setup mode:"
    echo ""
    echo "  [1] Basic setup (recommended)"
    echo "      • Configure display schedule only"
    echo "      • Uses standard defaults for server and PIR"
    echo "      • Quick 2-minute setup"
    echo ""
    echo "  [2] Advanced setup"
    echo "      • Customize all settings"
    echo "      • Server IP/port, PIR timeout, GPIO pin"
    echo "      • For experienced users"
    echo ""
    
    local setup_mode
    while true; do
        read -rp "Choose mode [1]: " setup_mode
        setup_mode="${setup_mode:-1}"
        case "$setup_mode" in
            1) break ;;
            2) break ;;
            *) echo "Please enter 1 or 2" ;;
        esac
    done
    
    # === Schedule Configuration (both modes) ===
    echo ""
    print_header "Display Schedule"
    print_info "Default schedule:"
    print_info "  Monday-Friday: 16:00 to 20:45 (4:00 PM to 8:45 PM)"
    print_info "  Saturday-Sunday: 08:00 to 20:45 (8:00 AM to 8:45 PM)"
    echo ""
    
    if ! ask_yes_no "Use default schedule?"; then
        print_info "Enter custom schedule times (format: HH:MM-HH:MM)"
        echo ""
        
        # Get Monday-Friday schedule
        read -rp "Monday-Friday (default 16:00-20:45): " weekday_schedule
        weekday_schedule="${weekday_schedule:-16:00-20:45}"
        
        # Get Saturday-Sunday schedule
        read -rp "Saturday-Sunday (default 08:00-20:45): " weekend_schedule
        weekend_schedule="${weekend_schedule:-08:00-20:45}"
        
        MONDAY_FRIDAY="$weekday_schedule"
        SATURDAY_SUNDAY="$weekend_schedule"
    else
        # Use defaults
        MONDAY_FRIDAY="16:00-20:45"
        SATURDAY_SUNDAY="08:00-20:45"
    fi
    
    # === Advanced Settings (mode 2 only) ===
    if [[ "$setup_mode" == "2" ]]; then
        echo ""
        print_header "Server Connection Settings"
        print_info "The Raspberry Pi connects to this server to display MagicMirror"
        echo ""
        
        read -rp "Server IP address (default 192.168.4.45): " server_ip_input
        SERVER_IP="${server_ip_input:-192.168.4.45}"
        
        read -rp "Server port (default 8036): " server_port_input
        SERVER_PORT="${server_port_input:-8036}"
        
        echo ""
        print_header "PIR Motion Sensor Settings"
        print_info "The PIR sensor automatically turns the display on/off based on motion"
        echo ""
        
        read -rp "Timeout in minutes before display turns off (default 5): " pir_timeout_input
        PIR_TIMEOUT_MINUTES="${pir_timeout_input:-5}"
        
        read -rp "GPIO pin number for PIR sensor - BCM numbering (default 24): " pir_pin_input
        PIR_GPIO_PIN="${pir_pin_input:-24}"
    else
        # Basic mode - use defaults
        SERVER_IP="192.168.4.45"
        SERVER_PORT="8036"
        PIR_TIMEOUT_MINUTES="5"
        PIR_GPIO_PIN="24"
    fi
    
    # === Debug Mode (both modes) ===
    echo ""
    print_info "Debug mode provides detailed diagnostic output for troubleshooting."
    print_warning "Debug logs can be very verbose (15-30 MB/day). Only enable if troubleshooting issues."
    
    if ask_yes_no "Enable debug mode?" "n"; then
        DEBUG_MODE="true"
        print_info "Debug mode enabled - logs will be very detailed"
    else
        DEBUG_MODE="false"
        print_info "Debug mode disabled - only essential logs will be shown"
    fi
    
    # === Create config.conf ===
    print_info "Creating configuration file..."
    cat > "${SCRIPT_DIR}/config.conf" << EOF
# ============================================================================
# MagicMirror Digital Photo Frame Configuration
# ============================================================================
# Generated by setup_client.sh on $(date)
# 
# After changing this file, restart the service:
#   sudo systemctl restart digitalframe.service
# ============================================================================

# === Display Schedule ===
# Format: DAYRANGE=HH:MM-HH:MM (ON_TIME-OFF_TIME in 24-hour format)

# Monday through Friday schedule (ON_TIME-OFF_TIME)
MONDAY_FRIDAY=$MONDAY_FRIDAY

# Saturday and Sunday schedule (ON_TIME-OFF_TIME)
SATURDAY_SUNDAY=$SATURDAY_SUNDAY

# === Server Connection ===
# MagicMirror server address (typically your NAS or server)

SERVER_IP=$SERVER_IP
SERVER_PORT=$SERVER_PORT

# === PIR Motion Sensor ===
# Automatic display power management based on motion detection

# Minutes of inactivity before turning off display
PIR_TIMEOUT_MINUTES=$PIR_TIMEOUT_MINUTES

# GPIO pin number for PIR sensor - BCM numbering
PIR_GPIO_PIN=$PIR_GPIO_PIN

# === Debug Mode ===
# Enable detailed diagnostic logging for troubleshooting
# WARNING: Debug mode generates 15-30 MB of logs per day!

DEBUG=$DEBUG_MODE

# ============================================================================
# For more information, see README.md
# ============================================================================
EOF
    
    print_success "Configuration complete:"
    print_info "  Schedule: Monday-Friday $MONDAY_FRIDAY, Saturday-Sunday $SATURDAY_SUNDAY"
    print_info "  Server: ${SERVER_IP}:${SERVER_PORT}"
    print_info "  PIR timeout: ${PIR_TIMEOUT_MINUTES} minutes (GPIO pin ${PIR_GPIO_PIN})"
    print_info "  Debug mode: $DEBUG_MODE"
    print_info "  Config file: ${SCRIPT_DIR}/config.conf"
    echo ""
}

# ============================================================================
# Configure Journald Logging
# ============================================================================

configure_journald() {
    print_header "Configure System Logging (journald)"
    
    print_info "The Digital Photo Frame uses systemd journal for all logging."
    print_info "To prevent logs from consuming too much disk space, we'll set limits:"
    echo ""
    print_info "  • Maximum disk usage: 64 MB"
    print_info "  • Maximum retention: 3 days"
    print_info "  • Automatic rotation when limits are reached"
    echo ""
    
    if ! ask_yes_no "Configure journald log limits now?" "y"; then
        print_warning "Skipping journald configuration"
        print_info "You can configure manually later by editing /etc/systemd/journald.conf"
        echo ""
        return 0
    fi
    
    print_info "Creating journald configuration drop-in..."
    
    # Create journald drop-in directory
    if [[ ! -d /etc/systemd/journald.conf.d ]]; then
        print_info "Creating /etc/systemd/journald.conf.d/ directory..."
        sudo mkdir -p /etc/systemd/journald.conf.d
    fi
    
    # Create drop-in configuration file
    sudo tee /etc/systemd/journald.conf.d/digitalframe.conf > /dev/null <<'EOF'
# Digital Photo Frame - Journald Configuration
# Generated by setup_client.sh
# Prevents logs from consuming excessive disk space

[Journal]
# Maximum disk space for all persistent journals
SystemMaxUse=64M

# Maximum size for individual journal files (triggers rotation)
SystemMaxFileSize=8M

# Maximum disk space for volatile (RAM) journals
RuntimeMaxUse=32M

# Maximum age of journal entries (3 days)
MaxRetentionSec=3d

# Do not forward to syslog (avoid duplication)
ForwardToSyslog=no
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "Journald configuration created: /etc/systemd/journald.conf.d/digitalframe.conf"
    else
        print_error "Failed to create journald configuration"
        return 1
    fi
    
    # Restart journald to apply changes
    print_info "Restarting systemd-journald to apply configuration..."
    sudo systemctl restart systemd-journald
    
    if [[ $? -eq 0 ]]; then
        print_success "Journald restarted successfully"
        
        # Show current disk usage
        local disk_usage
        disk_usage=$(journalctl --disk-usage 2>/dev/null | grep -oP 'currently use \K[^ ]+' || echo "unknown")
        print_info "Current journal disk usage: ${disk_usage}"
    else
        print_error "Failed to restart journald (configuration may not be active)"
        return 1
    fi
    
    CONFIGURED_JOURNALD=true
    
    echo ""
}

# ============================================================================
# Configure Systemd
# ============================================================================

configure_systemd() {
    print_header "Installing Digital Photo Frame Service"
    
    if [[ ! -d "$SCRIPT_DIR/systemd" ]]; then
        print_error "Systemd directory not found: ${SCRIPT_DIR}/systemd"
        return 1
    fi
    
    # Get current user's UID for XDG_RUNTIME_DIR
    local user_uid
    user_uid=$(id -u)
    
    # Install unified service file
    print_info "Installing digitalframe.service..."
    
    if [[ -f "$SCRIPT_DIR/systemd/digitalframe.service" ]]; then
        # Replace placeholders with actual values
        sed -e "s|__USER__|${USER}|g" \
            -e "s|__UID__|${user_uid}|g" \
            -e "s|__INSTALL_DIR__|${SCRIPT_DIR}|g" \
            "$SCRIPT_DIR/systemd/digitalframe.service" | sudo tee "/etc/systemd/system/digitalframe.service" > /dev/null
        print_success "Installed: digitalframe.service"
    else
        print_error "Service file not found: digitalframe.service"
        return 1
    fi
    
    # Reload systemd
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    # Enable service (will start on boot)
    print_info "Enabling systemd service..."
    sudo systemctl enable digitalframe.service
    
    print_success "Digital Photo Frame service enabled (will start on boot)"
    echo ""
    
    # Ask to start service now
    if ask_yes_no "Start Digital Photo Frame service now?"; then
        print_info "Starting digitalframe service..."
        sudo systemctl start digitalframe.service
        sleep 2
        
        # Check if service started successfully
        if systemctl is-active --quiet digitalframe.service; then
            print_success "Service started successfully!"
            print_info "Check status: systemctl status digitalframe.service"
            print_info "View logs: journalctl -fu digitalframe.service"
        else
            print_error "Service failed to start. Check logs: journalctl -xeu digitalframe.service"
        fi
    else
        print_info "Service will start on next boot"
        print_info "To start manually: sudo systemctl start digitalframe.service"
    fi
    
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
        print_info "✓ Systemd service installed and enabled"
        print_info "  - Schedule file: ${SCRIPT_DIR}/schedule.conf"
        print_info "  - Monday-Friday: ${MONDAY_FRIDAY:-16:00-20:45}"
        print_info "  - Saturday-Sunday: ${SATURDAY_SUNDAY:-08:00-20:45}"
    fi
    
    if [[ "$CONFIGURED_JOURNALD" == true ]]; then
        print_info "✓ Journald logging configured (64MB max, 3-day retention)"
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
        echo "  Start:   sudo systemctl start digitalframe.service"
        echo "  Stop:    sudo systemctl stop digitalframe.service"
        echo "  Status:  systemctl status digitalframe.service"
        echo "  Logs:    journalctl -fu digitalframe.service"
        echo ""
        print_info "To modify schedule:"
        echo "  1. Edit: nano ${SCRIPT_DIR}/schedule.conf"
        echo "  2. Restart: sudo systemctl restart digitalframe.service"
        echo ""
    fi
    
    print_info "Troubleshooting:"
    echo "  Server test:     $SCRIPT_DIR/check_server.sh"
    echo "  View logs:       journalctl -fu digitalframe.service"
    echo "  Documentation:   $REPO_ROOT/AGENTS.md"
    echo ""
    
    if [[ "$SCHEDULING_METHOD" == "none" ]]; then
        print_success "Setup complete! Use manual control commands to start MagicMirror."
    else
        print_success "Setup complete! Digital Photo Frame will start automatically on next boot."
        print_info "Service is currently: $(systemctl is-active digitalframe.service 2>/dev/null || echo 'not running')"
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
    print_info "  • Configure journald for log management"
    print_info "  • Configure systemd for automatic scheduling"
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
        configure_schedule
        configure_journald
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
