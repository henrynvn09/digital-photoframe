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

**Systemd:**
```bash
# View MagicMirror logs
journalctl -u digitalframe.service -n 50

# Follow logs in real-time
journalctl -fu digitalframe.service
```

**Manual script logs** (debug mode only):
```bash
# MagicMirror runtime logs
tail -f /tmp/magicmirror.log

# PIR sensor logs
tail -f /tmp/pir.log
```

### Modify Schedule

Edit the schedule configuration file:
```bash
# Edit schedule times
nano ~/digital-photoframe/client/schedule.conf

# Restart service to apply changes
sudo systemctl restart digitalframe.service
```

---

## PIR Sensor Setup

### Hardware

- **PIR Motion Sensor** connected to GPIO pin 24
- VCC → 5V
- GND → Ground
- OUT → GPIO 24

### Configuration

Edit `client/pir-control-display/pir.py`:

```python
SHUTOFF_DELAY = 15 * 60  # seconds (15 minutes)
PIR_PIN = 24             # GPIO pin number
DEBUG = False            # Set to True for verbose logging
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

If your digital photo frame isn't working as expected, enable debug logging:

```bash
# 1. Edit schedule config
nano ~/digital-photoframe/client/schedule.conf

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
# Set DEBUG=false in schedule.conf, then restart service
```

### View Detailed Error Logs

```bash
# Systemd
journalctl -xeu digitalframe.service -n 100

# Manual script logs (debug mode)
tail -100 /tmp/magicmirror.log
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
│   ├── schedule.conf          # Schedule configuration (weekday/weekend times)
│   ├── magicmirror-manager.sh # Schedule monitor and lifecycle manager
│   ├── setup_client.sh        # Automated setup script
│   ├── check_server.sh        # Server connectivity checker
│   ├── mm.sh                  # MagicMirror client launcher
│   ├── turn_on_magic_mirror.sh   # Start script
│   └── turn_off_magic_mirror.sh  # Stop script
├── AGENTS.md                  # Detailed technical documentation
└── README.md                  # This file
```

---

## Configuration

### Server IP and Port

Default: `192.168.4.45:8036`

To change, edit these files:
- `client/check_server.sh` (lines 6-7)
- `client/mm.sh` (lines 6-7)
- `client/turn_on_magic_mirror.sh` (lines 13-14)

### Schedule Times

Default schedule:
- **Weekends**: ON at 8:00 AM, OFF at 8:45 PM
- **Weekdays**: ON at 4:00 PM, OFF at 8:45 PM

Modify by editing `client/schedule.conf` and restarting the service (see [Usage](#modify-schedule) section).

### PIR Timeout

Default: 15 minutes

Edit `client/pir-control-display/pir.py`:
```python
SHUTOFF_DELAY = 15 * 60  # Change to desired seconds
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
