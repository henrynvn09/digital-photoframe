# AGENTS.md - MagicMirror Digital Photo Frame Configuration

## Project Overview

This is a MagicMirror² configuration repository for a digital photo frame using a 27-inch monitor. The system uses a client-server architecture with:
- **Server**: MagicMirror running in Docker on a Synology NAS
- **Client**: Raspberry Pi displaying the interface via client-only mode
- **Display Control**: PIR motion sensor for automatic power management

### Purpose
Create a family digital photo frame that displays:
- Photos from Immich (self-hosted photo management)
- Google Calendar events (in Vietnamese)
- Microsoft To-Do tasks
- Weather forecast
- World clock showing Vietnam time
- All with automatic display on/off based on motion detection

## Architecture

### Server Side (NAS)
- Runs MagicMirror in Docker container
- Serves the interface on port 8036 (mapped from internal 8080)
- Hosts configuration, modules, and custom CSS
- Timezone: America/Los_Angeles
- Location: Latitude 33.8992463, Longitude -118.0689099

### Client Side (Raspberry Pi 3B)
- Connects to NAS server at 192.168.4.45:8036
- Runs in client-only mode (no local server)
- **Uses X11 mode** (forced for optimal Pi 3B performance)
- **Scheduled startup/shutdown** using unified systemd service:
  - Single always-running service monitors schedule every 30 seconds
  - Automatically starts/stops MagicMirror based on configured times
  - **Default schedule**: Weekends 8:00 AM - 8:45 PM, Weekdays 4:00 PM - 8:45 PM
  - Configurable via `client/schedule.conf`
- PIR motion sensor on GPIO pin 24 for smart display control
- **Auto-restart on crash** (systemd service management)

### Display Power Management
- PIR sensor detects motion and turns display on
- 15-minute idle timeout before automatic shutdown
- Uses vcgencmd for display power control
- Event-driven architecture to minimize CPU usage

## MagicMirror Modules

### Default Modules
1. **clock** (top_left): Local time, no seconds
2. **calendar** (top_center): Google Calendar with Vietnamese header "CUỘC HẸN SẮP TỚI"
3. **alert**: System alerts

### Third-Party Modules
1. **MMM-Worldclock** (top_left): Vietnam time display with flag
2. **MMM-MicrosoftToDo** (top_right): To-do list with Vietnamese header "Việc cần làm"
   - OAuth2 authentication
   - Shows checkboxes, due dates, relative dates
   - Highlights tags with yellow color (#E3FF30)
   - Ordered by due date
3. **MMM-OpenWeatherMapForecast** (bottom_center): Weather forecast using OpenWeatherMap API
   - Fork: henrynvn09/MMM-OpenWeatherMapForecast
4. **MMM-ImmichSlideShow** (fullscreen_below): Photo slideshow from Immich
   - Search mode with configurable query
   - Shows date, geo location, and photo count
   - 30-second timeout per image
   - 1000 image limit, sorted by creation date

## File Structure

```
digital-photoframe/
├── server/
│   ├── config/
│   │   ├── config.js          # Main MagicMirror configuration
│   │   ├── config.js.sample   # Template with empty API keys
│   │   └── config.js.bak      # Backup configuration
│   └── css/
│       └── custom.css         # Custom styling for modules
├── client/
│   ├── pir-control-display/
│   │   ├── pir.py             # PIR motion sensor control script
│   │   ├── turn_on_display.sh # Manual display on script
│   │   └── turn_off_display.sh# Manual display off script
│   ├── systemd/
│   │   └── digitalframe.service # Unified systemd service for scheduling
│   ├── schedule.conf          # Schedule configuration (weekday/weekend times)
│   ├── magicmirror-manager.sh # Schedule monitor and lifecycle manager
│   ├── check_server.sh        # Server connectivity checker
│   ├── mm.sh                  # MagicMirror client startup script
│   ├── turn_on_magic_mirror.sh# Start MagicMirror client + PIR
│   └── turn_off_magic_mirror.sh# Stop MagicMirror client + PIR
├── .gitmodules                # Git submodules configuration
├── AGENTS.md                  # This file
└── README.md                  # User documentation
```

## Build/Test Commands

### Server (NAS Docker)
```bash
# Run MagicMirror server
docker run -d --name magicmirror \
  --publish 8036:8080 \
  --restart unless-stopped \
  -e TZ=America/Los_Angeles \
  --volume /volume1/docker/magicmirror/config:/opt/magic_mirror/config \
  --volume /volume1/docker/magicmirror/modules:/opt/magic_mirror/modules \
  --volume /volume1/docker/magicmirror/css:/opt/magic_mirror/css \
  karsten13/magicmirror:latest

# Install module dependencies inside Docker
docker exec -it magicmirror /bin/bash
cd /opt/magic_mirror/modules/MODULE_NAME
npm install
```

### Client (Raspberry Pi)

#### Manual Control (Debug/Testing)
```bash
# Start MagicMirror and PIR manually
./client/turn_on_magic_mirror.sh

# Stop MagicMirror and PIR
./client/turn_off_magic_mirror.sh

# View logs
tail -f /tmp/magicmirror.log
tail -f /tmp/pir.log

# Manual display control
./client/pir-control-display/turn_on_display.sh
./client/pir-control-display/turn_off_display.sh

# Check server connectivity
./client/check_server.sh
```

#### Systemd Service (Automatic Scheduling)
```bash
# View service status
systemctl status digitalframe.service

# View logs in real-time
journalctl -fu digitalframe.service

# View recent logs
journalctl -u digitalframe.service -n 50

# Restart service (after config change)
sudo systemctl restart digitalframe.service

# Enable/disable auto-start on boot
sudo systemctl enable digitalframe.service
sudo systemctl disable digitalframe.service
```

### Testing Changes
1. Modify configuration files
2. Restart MagicMirror Docker container on NAS
3. Client will automatically reconnect and reload
4. No package.json - this is a configuration-only project

## Code Style Guidelines

### JavaScript (config.js)
- Use `let` instead of `var` for variable declarations
- Use tabs for indentation
- Single-line comments: `//`
- Multi-line comments: `/* */`
- Keep API keys empty in committed files
- Use trailing commas in arrays and objects

### Python (pir.py)
- Use snake_case for variables and functions
- Declare global variables explicitly with `global` keyword
- Use proper imports (absolute, then relative)
- Type hints for function signatures
- Proper error handling with try/except
- Use f-strings for formatting

### CSS (custom.css)
- Use kebab-case for class names
- Use rgba() for colors with transparency
- Consistent spacing: properties indented with 2 spaces
- Group related selectors
- Background transparency: rgba(0,0,0,0.6)
- Border radius: 8px for modules

### Shell Scripts
- Use `#!/bin/bash` shebang
- Set error handling: `set -euo pipefail`
- Quote variables: `"${VAR}"`
- Use absolute paths for reliability
- Add comments for complex logic

## Configuration Details

### Required API Keys/Tokens
- **OpenWeatherMap**: API key for weather data
- **Immich**: API key for photo access
- **Microsoft To-Do**: OAuth2 client ID, client secret, refresh token
- **Google Calendar**: Calendar URL (private iCal link)

### Network Configuration
- Server IP: 192.168.4.45
- Server Port: 8036
- Raspberry Pi must be on same network
- IP whitelist must include Pi's IP for remote access
- Server connectivity is checked before MagicMirror starts (5 attempts, 3-second delay)

### Schedule Configuration (Raspberry Pi)

Schedule is configured in `client/schedule.conf` using time range format:
```ini
# Format: DAYRANGE=HH:MM-HH:MM (ON_TIME-OFF_TIME)
MONDAY_FRIDAY=16:00-20:45
SATURDAY_SUNDAY=08:00-20:45
```

- **Monday-Friday**: Display ON at 16:00 (4 PM), OFF at 20:45 (8:45 PM)
- **Saturday-Sunday**: Display ON at 08:00 (8 AM), OFF at 20:45 (8:45 PM)
- Schedule is checked every 30 seconds by the systemd service
- Changes take effect after restarting the service: `sudo systemctl restart digitalframe.service`

To modify schedule times:
```bash
nano ~/digital-photoframe/client/schedule.conf
sudo systemctl restart digitalframe.service
```

**Format rules:**
- Time format: HH:MM (24-hour, zero-padded recommended but not required)
- Range separator: dash `-` (no spaces)
- Valid times: 00:00 to 23:59
- Midnight crossover NOT supported (times must be same-day only)
- Examples:
  - `MONDAY_FRIDAY=06:00-22:30` (6 AM to 10:30 PM on weekdays)
  - `SATURDAY_SUNDAY=08:00-23:00` (8 AM to 11 PM on weekends)
  - `MONDAY_FRIDAY=09:00-17:00` (Standard 9-to-5 work hours)

### PIR Sensor Configuration
- GPIO Pin: 24
- Shutoff Delay: 15 minutes (900 seconds)
- vcgencmd path: /usr/bin/vcgencmd
- Debug mode: Disabled by default
- Event-driven: Uses gpiozero callbacks for efficiency

## Vietnamese Language Settings

The interface uses Vietnamese text for certain headers:
- Calendar header: "CUỘC HẸN SẮP TỚI" (Upcoming Appointments)
- To-Do header: "Việc cần làm" (Things to Do)
- Vietnam clock label: "VIETNAM"
- Calendar symbol: "lich trong nha" (household calendar)

When modifying headers or adding new modules, maintain consistency with Vietnamese text where appropriate.

## Notes for Agents

### Security
- Never commit API keys or credentials to the repository
- Use config.js.sample as a template with empty keys
- All sensitive data should be in .gitignore

### Testing Workflow
1. Make changes to config/CSS files
2. Restart MagicMirror Docker container on NAS
3. Verify changes appear on Raspberry Pi display
4. Check for errors in Docker logs and Pi logs
5. Test PIR sensor functionality if display control changed

### Module Management
- All third-party modules must be installed in Docker environment
- Run `npm install` inside Docker container for each module
- Fork henrynvn09/MMM-OpenWeatherMapForecast used for weather
- Modules are git submodules where applicable

### Layout and Positioning
- Top Left: clock, world clock
- Top Center: calendar (with 100px left margin)
- Top Right: Microsoft To-Do
- Bottom Center: weather forecast
- Fullscreen Below: Immich slideshow (background layer)

### Styling Consistency
- All modules have semi-transparent black background: rgba(0,0,0,0.6)
- 8px border radius for rounded corners
- 10px padding inside modules
- Font sizes: 1.7-1.8em for better visibility on 27" display
- Bottom-right image info positioned at bottom: 400px, right: 100px

### Common Tasks
- **Update photos**: Modify Immich query in config.js
- **Add calendar**: Add new object to calendars array
- **Change weather location**: Update latitude/longitude
- **Adjust display timeout**: Modify SHUTOFF_DELAY in pir.py
- **Change schedule**: Edit `client/schedule.conf` and restart service

## Troubleshooting

### Black Screen / Blackout Issue

**Symptom:** Display shows black screen with cursor visible, but no MagicMirror interface

**Root Cause:** MagicMirror client crashes immediately on startup due to incorrect launch method

**Solution:**
1. Check logs: `journalctl -u digitalframe.service -n 100`
2. Look for error: `"clientonly is not running code null"` - indicates Electron startup failure
3. **Fixed in current version** by using npm scripts instead of direct Electron launch
4. Ensure `check_server.sh` confirms server connectivity before starting
5. Force X11 mode (Pi 3B performs better with X11 than Wayland)

**Prevention:**
- Use systemd services for auto-restart on crash
- Enable server connectivity check in startup scripts
- Monitor process health with systemd or script monitoring loop

### MagicMirror Won't Start

**Common Issues:**

1. **Server unreachable**
   ```bash
   # Test connectivity
   ./client/check_server.sh
   # Or manually
   nc -zv 192.168.4.45 8036
   ```

2. **Stale lock file**
   ```bash
   # Remove manually
   rmdir /tmp/mm_instance.lock
   ```

3. **Process already running**
   ```bash
   # Kill existing processes
   pkill -9 -f electron
   pkill -9 -f "pir.py"
   ```

### PIR Sensor Not Working

**Symptoms:** Display doesn't turn on/off with motion

**Solutions:**
1. Check PIR service status:
   ```bash
   systemctl status digitalframe.service
   # Or check process directly
   ps aux | grep pir.py
   ```

2. Test PIR manually:
   ```bash
   # Adjust path to your installation directory
   python3 ~/digital-photoframe/client/pir-control-display/pir.py
   # Wave hand in front of sensor, check for log output
   ```

3. Check GPIO permissions:
   ```bash
   # Replace 'pi' with your actual username if different
   sudo usermod -a -G gpio $(whoami)
   # Logout and login again
   ```

4. Verify vcgencmd works:
   ```bash
   vcgencmd display_power  # Check current state
   vcgencmd display_power 1  # Turn on
   vcgencmd display_power 0  # Turn off
   ```

### Debugging with Debug Mode

**Enable detailed diagnostic logging when troubleshooting scheduler issues:**

1. **Edit schedule configuration:**
   ```bash
   nano ~/digital-photoframe/client/schedule.conf
   ```

2. **Enable debug mode:**
   ```ini
   DEBUG=true
   ```

3. **Restart the service:**
   ```bash
   sudo systemctl restart digitalframe.service
   ```

4. **View debug logs in real-time:**
   ```bash
   journalctl -fu digitalframe.service
   ```

**What debug logs show:**
- Loop iteration numbers and timestamps (every 30 seconds)
- Schedule calculation details (time math, day type detection)
- State transition decisions with reasons
- Function entry/exit points (>>> and <<<)
- All variable values at decision points
- Command outputs (vcgencmd, process checks, server connectivity)
- Error traps for failed commands

**Example debug output:**
```
[2025-12-22 10:47:24] [DEBUG] Loop iteration #1 starting at 10:47:24
[2025-12-22 10:47:24] [DEBUG] Current state: OFF
[2025-12-22 10:47:24] [DEBUG] >>> should_be_running() called
[2025-12-22 10:47:24] [DEBUG] Current time: hour=10, minute=47, day=2 (Tuesday)
[2025-12-22 10:47:24] [DEBUG] Day type: WEEKDAY, on_min=960 (from 16:00)
[2025-12-22 10:47:24] [DEBUG] Result: FALSE (should be OFF)
[2025-12-22 10:47:24] [DEBUG] Reason: current_min=647 is outside window [960, 1245)
```

**IMPORTANT:** Disable debug mode after troubleshooting to reduce log verbosity:
```bash
# Set DEBUG=false in schedule.conf
sudo systemctl restart digitalframe.service
```

### Viewing Logs

**Systemd:**
```bash
journalctl -u digitalframe.service -n 50
journalctl -fu digitalframe.service  # Follow mode
```

**Manual script logs** (if not using systemd scheduling):
```bash
tail -f /tmp/magicmirror.log
tail -f /tmp/pir.log
```

### Performance Optimization (Raspberry Pi 3B)

**Best Practices:**
- ✅ Use X11 mode (forced in current scripts)
- ✅ Disable unused MagicMirror modules
- ✅ Reduce image slideshow size/frequency
- ✅ Set calendar fetch interval to 1 hour (not every minute)
- ✅ Disable MagicMirror update notifications
- ✅ Use event-driven PIR (already implemented)

**If still slow:**
1. Check CPU usage: `top`
2. Check memory: `free -h`
3. Reduce Electron flags in mm.sh
4. Consider upgrading to Pi 4 for better performance
