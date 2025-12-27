# MagicMirror Digital Photo Frame

My MagicMirror configuration for a digital photo frame using a 27-inch monitor. It syncs Google Calendar, Microsoft To-Do, and shows images from Immich with PIR motion sensor control.

<img src="https://github.com/user-attachments/assets/06a367d3-47bb-4454-9f28-7fd8bd04826f" height="500">

## Features

- 🖼️ **Photo Slideshow** - Displays photos from self-hosted Immich server
- 📅 **Google Calendar** - Shows upcoming events in Vietnamese
- ✅ **Microsoft To-Do** - Displays task list with due dates
- 🌤️ **Weather Forecast** - OpenWeatherMap integration
- 🌍 **World Clock** - Shows Vietnam time with flag
- 👋 **PIR Motion Sensor** - Automatically turns display on/off based on motion
- ⏰ **Auto Scheduling** - Schedule-aware service, different times for weekdays/weekends
- 🔄 **Auto-Restart** - Automatically recovers from crashes (with systemd)

## Architecture

- **Server**: MagicMirror running in Docker on Synology NAS (port 8036)
- **Client**: Raspberry Pi 3B displaying the interface via client-only mode
- **Display Control**: PIR motion sensor on GPIO pin 24 for power management

---

## Quick Start (Raspberry Pi Client)

### Prerequisites

1. **Raspberry Pi** (tested on Pi 3B) with Raspberry Pi OS
2. **MagicMirror installed** on the Pi:
   ```bash
   bash -c "$(curl -sL https://raw.githubusercontent.com/sdetweil/MagicMirror_scripts/master/raspberry.sh)"
   ```
3. **MagicMirror server** running on your NAS (see Server Setup below)
4. **This repository** cloned to your Pi:
   ```bash
   cd ~
   git clone <your-repo-url> digital-photoframe
   cd digital-photoframe
   ```
   
   > **Note:** You can clone to any directory. The scripts automatically detect their location.

### Automated Setup (Recommended)

Run the automated setup script:

```bash
cd ~/digital-photoframe/client
./setup_client.sh
```

The setup script will:
- ✅ Check prerequisites and system requirements
- ✅ Install required dependencies (python3, gpiozero, netcat)
- ✅ Configure GPIO permissions for PIR sensor
- ✅ Test connectivity to your MagicMirror server
- ✅ Configure schedule and install unified systemd service
- ✅ Make all scripts executable

**Follow the on-screen prompts** - the script will ask for your permission before making changes.

---

## Server Setup (NAS)

### Run MagicMirror in Docker

```bash
docker run -d --name magicmirror \
  --publish 8036:8080 \
  --restart unless-stopped \
  -e TZ=America/Los_Angeles \
  --volume /volume1/docker/magicmirror/config:/opt/magic_mirror/config \
  --volume /volume1/docker/magicmirror/modules:/opt/magic_mirror/modules \
  --volume /volume1/docker/magicmirror/css:/opt/magic_mirror/css \
  karsten13/magicmirror:latest
```

### Install Modules

All third-party modules must have dependencies installed **inside** the Docker container:

```bash
# Enter Docker container
docker exec -it magicmirror /bin/bash

# Navigate to module directory
cd /opt/magic_mirror/modules/MMM-ModuleName

# Install dependencies
npm install

# Exit container
exit

# Restart MagicMirror
docker restart magicmirror
```

### Required Modules

- `MMM-MicrosoftToDo` - To-do list integration
- `MMM-Worldclock` - World clock display
- `MMM-ImmichSlideShow` - Photo slideshow from Immich
- **`henrynvn09/MMM-OpenWeatherMapForecast`** - Weather forecast (custom fork)

### Configuration Files

1. **`server/config/config.js`** - Main MagicMirror configuration
   - Copy from `config.js.sample` and fill in your API keys
2. **`server/css/custom.css`** - Custom styling for modules

---

## Usage

### Start Early

Want to turn on the display before the scheduled time?

```bash
~/digital-photoframe/client/start_early.sh
```

**What it does:**
- Starts MagicMirror early (before scheduled ON time)
- Keeps it running until the next scheduled OFF time
- Interactive prompt with full status and schedule details
- Shows "no action needed" if already within schedule window
- Automatically returns to normal schedule after OFF time

**Example usage (starting early):**

```bash
$ ~/digital-photoframe/client/start_early.sh

═══════════════════════════════════════════════════════════════════════════════
                               STATUS
═══════════════════════════════════════════════════════════════════════════════
Current time:     14:30 (2:30 PM)
Override status:  Inactive (following normal schedule)
MagicMirror:      OFF (waiting for scheduled ON time)

═══════════════════════════════════════════════════════════════════════════════
                            TODAY'S SCHEDULE
═══════════════════════════════════════════════════════════════════════════════
Scheduled ON:     16:00 (4:00 PM)  →  in 1h 30m
Scheduled OFF:    20:45 (8:45 PM)

═══════════════════════════════════════════════════════════════════════════════
                            PROPOSED ACTION
═══════════════════════════════════════════════════════════════════════════════
Start MagicMirror NOW and keep it running until scheduled OFF time

This will:
  • Turn on the display immediately
  • Start MagicMirror within 30 seconds
  • Keep running until 20:45 (8:45 PM) today
  • Then automatically return to normal schedule

Do you want to START EARLY? [Y/n]: ↵
[2025-12-26 14:30:17] ✓ Early start activated
[2025-12-26 14:30:17]   MagicMirror will start within 30 seconds
```

**To cancel early start:**

Run the same command again - it detects the current state and prompts you to cancel:

```bash
$ ~/digital-photoframe/client/start_early.sh

═══════════════════════════════════════════════════════════════════════════════
                               STATUS
═══════════════════════════════════════════════════════════════════════════════
Current time:     14:35 (2:35 PM)
Override status:  ACTIVE (started early)
MagicMirror:      ON (forced until scheduled OFF time)

═══════════════════════════════════════════════════════════════════════════════
                            PROPOSED ACTION
═══════════════════════════════════════════════════════════════════════════════
Cancel early start and return to normal schedule

This will:
  • Remove the early start override
  • MagicMirror will stop (outside scheduled hours)
  • Return to normal automatic scheduling
  • Changes take effect within 30 seconds

Do you want to CANCEL early start? [Y/n]: ↵
[2025-12-26 14:35:22] ✓ Early start cancelled
[2025-12-26 14:35:22]   Returning to normal schedule
```

**Inside schedule window:**

If you run the script during scheduled hours, it shows:

```bash
$ ~/digital-photoframe/client/start_early.sh

═══════════════════════════════════════════════════════════════════════════════
                               STATUS
═══════════════════════════════════════════════════════════════════════════════
Current time:     17:00 (5:00 PM)
MagicMirror:      ON (within scheduled hours)

═══════════════════════════════════════════════════════════════════════════════
                            TODAY'S SCHEDULE
═══════════════════════════════════════════════════════════════════════════════
Scheduled ON:     16:00 (4:00 PM)  →  PASSED 1h ago
Scheduled OFF:    20:45 (8:45 PM)  →  in 3h 45m

═══════════════════════════════════════════════════════════════════════════════
                          NO ACTION NEEDED
═══════════════════════════════════════════════════════════════════════════════
MagicMirror is already running according to schedule.
No need to start early - you're within the scheduled time window.
```

**Limitations:**
- Cannot start early if current time is past today's scheduled OFF time
- Changes take effect within 30 seconds (manager check interval)
- During scheduled hours, script shows informational message only

### Manual Control (Debug/Testing Only)

The manual scripts are provided for debugging and testing purposes. For regular operation, use systemd scheduling (configured during setup).

Run these commands from your shell:

```bash
# Start MagicMirror and PIR sensor
~/digital-photoframe/client/turn_on_magic_mirror.sh

# Stop MagicMirror and PIR sensor
~/digital-photoframe/client/turn_off_magic_mirror.sh

# Check server connectivity
~/digital-photoframe/client/check_server.sh

# Manual display control
~/digital-photoframe/client/pir-control-display/turn_on_display.sh
~/digital-photoframe/client/pir-control-display/turn_off_display.sh
```

### View Logs

All logs are managed by systemd journal:

```bash
# View last 50 lines
journalctl -u digitalframe.service -n 50

# Follow logs in real-time
journalctl -fu digitalframe.service

# View logs from today only
journalctl -u digitalframe.service --since today

# View logs with timestamps
journalctl -u digitalframe.service -o short-iso

# Check disk usage
journalctl --disk-usage

# Manually clean old logs (if needed)
sudo journalctl --vacuum-time=3d
sudo journalctl --vacuum-size=8M
```

**Log retention**: Logs are automatically rotated and kept for 3 days with max 64MB disk usage (configured in `/etc/systemd/journald.conf.d/digitalframe.conf`).

### Modify Configuration

Edit the configuration file to change schedule, server settings, or PIR behavior:
```bash
# Edit configuration
nano ~/digital-photoframe/client/config.conf

# Restart service to apply changes
sudo systemctl restart digitalframe.service
```

**Available settings:**
- **Schedule**: `MONDAY_FRIDAY` and `SATURDAY_SUNDAY` (HH:MM-HH:MM format)
- **Server**: `SERVER_IP` and `SERVER_PORT` (your MagicMirror server address)
- **PIR Sensor**: `PIR_TIMEOUT_MINUTES` (default: 5) and `PIR_GPIO_PIN` (default: 24)
- **Debug Mode**: `DEBUG` (true/false - only enable when troubleshooting)

### Log Management

The system uses systemd journal for all logging with automatic rotation:

**Configuration** (`/etc/systemd/journald.conf.d/digitalframe.conf`):
- **SystemMaxUse**: 64MB - Maximum disk space for all journals
- **SystemMaxFileSize**: 2MB - Individual journal file size limit
- **RuntimeMaxUse**: 4MB - Maximum volatile memory usage
- **MaxRetentionSec**: 3 days - Automatic deletion of logs older than 3 days

**To check log sizes**:
```bash
journalctl --disk-usage
```

**To manually clean old logs**:
```bash
sudo journalctl --vacuum-time=3d  # Remove logs older than 3 days
sudo journalctl --vacuum-size=8M  # Limit to 64MB total
```

**No action required**: Logs rotate automatically when limits are reached.

---

## PIR Sensor Setup

### Hardware

- **PIR Motion Sensor** connected to GPIO pin 24
- VCC → 5V
- GND → Ground
- OUT → GPIO 24

### Configuration

The PIR sensor settings are configured in `client/config.conf`:

```ini
# Minutes of inactivity before turning off display (default: 5)
PIR_TIMEOUT_MINUTES=5

# GPIO pin number for PIR sensor - BCM numbering (default: 24)
PIR_GPIO_PIN=24
```

After changing settings, restart the service:
```bash
sudo systemctl restart digitalframe.service
```

### Testing PIR Sensor

```bash
# Run PIR script manually (adjust path to your installation)
python3 ~/digital-photoframe/client/pir-control-display/pir.py

# Wave hand in front of sensor
# Display should turn on, then off after 15 minutes of no motion
```

---

## Troubleshooting

### Black Screen with Cursor (Common Issue)

**Symptom:** Display shows black screen with cursor but no MagicMirror

**Solution:**
1. Check logs: `journalctl -u digitalframe.service -n 100`
2. Look for error: "clientonly is not running code null"
3. This has been fixed in the latest version - make sure you've run `git pull`

### MagicMirror Won't Start

```bash
# Test server connectivity (adjust path to your installation)
~/digital-photoframe/client/check_server.sh

# Check if server is reachable
nc -zv 192.168.4.45 8036

# Check for stale lock file
rmdir /tmp/mm_instance.lock

# Kill existing processes
pkill -9 -f electron
pkill -9 -f pir.py
```

### PIR Sensor Not Working

```bash
# Check GPIO permissions (replace 'pi' with your username)
groups $(whoami)  # Should include 'gpio'

# Add user to gpio group (replace 'pi' with your username if different)
sudo usermod -a -G gpio $(whoami)
# Then logout and login

# Test vcgencmd
vcgencmd display_power     # Check state
vcgencmd display_power 1   # Turn on
vcgencmd display_power 0   # Turn off

# Check PIR service status (systemd)
systemctl status digitalframe.service
```

### Debug Mode

⚠️ **WARNING**: Debug mode generates significantly more log output (~15-30 MB/day). With 64MB log limit, debug logs will fill up quickly and rotate frequently. Only enable temporarily for troubleshooting (minutes to hours, not days), then disable immediately.

If your digital photo frame isn't working as expected, enable debug logging:

```bash
# 1. Edit config file
nano ~/digital-photoframe/client/config.conf

# 2. Change DEBUG=false to DEBUG=true
# 3. Save and exit (Ctrl+X, Y, Enter)

# 4. Restart service
sudo systemctl restart digitalframe.service

# 5. Watch detailed logs in real-time
journalctl -fu digitalframe.service
```

Debug logs will show exactly what the scheduler is doing every 30 seconds, helping identify issues with:
- Schedule logic and time calculations
- Server connectivity
- Display control (vcgencmd)
- Process management

**Remember to disable debug mode after troubleshooting** to keep logs clean:
```bash
# Set DEBUG=false in config.conf, then restart service
sudo systemctl restart digitalframe.service
```

### View Detailed Error Logs

```bash
# View last 100 lines with error details
journalctl -xeu digitalframe.service -n 100

# View only error-priority messages
journalctl -u digitalframe.service -p err

# Export logs to file for analysis
journalctl -u digitalframe.service --since "1 hour ago" > ~/digitalframe_debug.log
```

For more troubleshooting, see [AGENTS.md](AGENTS.md#troubleshooting).

---

## Project Structure

```
digital-photoframe/
├── server/
│   ├── config/
│   │   ├── config.js          # Main MagicMirror configuration
│   │   └── config.js.sample   # Template (no API keys)
│   └── css/
│       └── custom.css         # Custom styling
├── client/
│   ├── systemd/
│   │   └── digitalframe.service  # Unified systemd service
│   ├── pir-control-display/
│   │   ├── pir.py             # PIR motion sensor script
│   │   └── turn_*_display.sh  # Manual display control
│   ├── config.conf            # Main configuration (schedule, server, PIR settings)
│   ├── magicmirror-manager.sh # Schedule monitor and lifecycle manager
│   ├── setup_client.sh        # Automated setup script
│   ├── check_server.sh        # Server connectivity checker
│   ├── mm.sh                  # MagicMirror client launcher
│   ├── start_early.sh         # Start MagicMirror early (before scheduled time)
│   ├── turn_on_magic_mirror.sh   # Start script
│   └── turn_off_magic_mirror.sh  # Stop script
├── AGENTS.md                  # Detailed technical documentation
└── README.md                  # This file
```

---

## Configuration

All settings are centralized in `client/config.conf`. After making changes, restart the service:

```bash
nano ~/digital-photoframe/client/config.conf
sudo systemctl restart digitalframe.service
```

### Available Settings

#### Display Schedule

Default schedule:
- **Monday-Friday**: 16:00 to 20:45 (4:00 PM to 8:45 PM)
- **Saturday-Sunday**: 08:00 to 20:45 (8:00 AM to 8:45 PM)

```ini
# Edit time ranges (HH:MM-HH:MM format, 24-hour clock)
MONDAY_FRIDAY=16:00-20:45
SATURDAY_SUNDAY=08:00-20:45
```

#### Server Connection

Default: `192.168.4.45:8036`

```ini
# Change to match your MagicMirror server
SERVER_IP=192.168.4.45
SERVER_PORT=8036
```

#### PIR Motion Sensor

Default: 5-minute timeout on GPIO pin 24

```ini
# Minutes before display turns off (no motion detected)
PIR_TIMEOUT_MINUTES=5

# GPIO pin (BCM numbering) - only change if using different pin
PIR_GPIO_PIN=24
```

#### Debug Mode

Default: `false` (disabled)

```ini
# Enable detailed logging (WARNING: generates 15-30 MB/day)
DEBUG=false
```

---

## Contributing

This is a personal project, but feel free to fork and adapt for your own use!

## License

MIT License - See repository for details

## Credits

- [MagicMirror²](https://magicmirror.builders/) - Open source smart mirror platform
- [MMM-ImmichSlideShow](https://github.com/jlp-craigmorten/MMM-ImmichSlideShow) - Immich integration
- [MMM-MicrosoftToDo](https://github.com/thobach/MMM-MicrosoftToDo) - To-Do integration
- Community modules and contributors

---

## Support

For issues or questions:
1. Check [AGENTS.md](AGENTS.md) for detailed technical documentation
2. Review [Troubleshooting](#troubleshooting) section above
3. Check logs: `journalctl -fu digitalframe.service`
