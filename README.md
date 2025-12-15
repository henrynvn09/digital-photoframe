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
- ⏰ **Auto Scheduling** - Different schedules for weekdays and weekends
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
   git clone <your-repo-url> magicmirror-config
   cd magicmirror-config
   ```
   
   > **Note:** You can clone to any directory. The scripts automatically detect their location.

### Automated Setup (Recommended)

Run the automated setup script:

```bash
cd ~/magicmirror-config/client
./setup_client.sh
```

The setup script will:
- ✅ Check prerequisites and system requirements
- ✅ Install required dependencies (python3, gpiozero, netcat)
- ✅ Configure GPIO permissions for PIR sensor
- ✅ Test connectivity to your MagicMirror server
- ✅ Set up automatic scheduling (cron or systemd)
- ✅ Make all scripts executable
- ✅ Run a test to verify everything works

**Follow the on-screen prompts** - the script will ask for your permission before making changes.

### Manual Setup (Alternative)

If you prefer to set up manually:

1. **Install dependencies:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y python3 python3-pip netcat-openbsd
   pip3 install --user gpiozero
   sudo usermod -a -G gpio pi
   ```

2. **Make scripts executable:**
   ```bash
   cd ~/magicmirror-config/client
   chmod +x *.sh
   chmod +x pir-control-display/*.sh
   ```

3. **Configure cron schedule:**
   ```bash
   crontab -e
   ```
   
   Add these lines (the `setup_client.sh` script does this automatically with correct absolute paths):
   ```bash
   # MagicMirror Environment
   SHELL=/bin/bash
   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   DISPLAY=:0
   XAUTHORITY=$HOME/.Xauthority
   XDG_RUNTIME_DIR=/run/user/1000

   # Weekends: ON at 8:00 AM, OFF at 8:45 PM
   # NOTE: Replace paths below with absolute paths from your installation
   0 8 * * 6,0 /bin/bash /home/USERNAME/magicmirror-config/client/turn_on_magic_mirror.sh >> $HOME/magicmirror_start.log 2>&1
   45 20 * * 6,0 /bin/bash /home/USERNAME/magicmirror-config/client/turn_off_magic_mirror.sh >> $HOME/magicmirror_stop.log 2>&1

   # Weekdays: ON at 4:00 PM, OFF at 8:45 PM
   0 16 * * 1-5 /bin/bash /home/USERNAME/magicmirror-config/client/turn_on_magic_mirror.sh >> $HOME/magicmirror_start.log 2>&1
   45 20 * * 1-5 /bin/bash /home/USERNAME/magicmirror-config/client/turn_off_magic_mirror.sh >> $HOME/magicmirror_stop.log 2>&1
   ```
   
   > **Important:** Replace `/home/USERNAME/magicmirror-config` with your actual absolute path. The `setup_client.sh` script handles this automatically.
   ```

4. **Test the setup:**
   ```bash
   # Test server connectivity
   ./check_server.sh
   
   # Start MagicMirror manually
   ./turn_on_magic_mirror.sh
   
   # Stop MagicMirror
   ./turn_off_magic_mirror.sh
   ```

### Systemd Setup (Optional but Recommended)

For better reliability with auto-restart on crash:

```bash
cd ~/magicmirror-config/client/systemd
cat INSTALL.md  # Read installation instructions
```

Or let the setup script install it for you when prompted.

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

### Manual Control

Run these commands from your shell (not cron - tilde expansion works here):

```bash
# Start MagicMirror and PIR sensor
~/magicmirror-config/client/turn_on_magic_mirror.sh

# Stop MagicMirror and PIR sensor
~/magicmirror-config/client/turn_off_magic_mirror.sh

# Check server connectivity
~/magicmirror-config/client/check_server.sh

# Manual display control
~/magicmirror-config/client/pir-control-display/turn_on_display.sh
~/magicmirror-config/client/pir-control-display/turn_off_display.sh
```

### View Logs

**Cron mode:**
```bash
# Startup logs
tail -f ~/magicmirror_start.log

# Shutdown logs
tail -f ~/magicmirror_stop.log

# MagicMirror runtime logs
tail -f /tmp/magicmirror.log

# PIR sensor logs
tail -f /tmp/pir.log
```

**Systemd mode:**
```bash
# View MagicMirror logs
journalctl -u magicmirror-client.service -n 50

# Follow logs in real-time
journalctl -fu magicmirror-client.service

# View PIR sensor logs
journalctl -u magicmirror-pir.service -n 50

# Check timer schedule
systemctl list-timers magicmirror-*
```

### Modify Schedule

**Cron:**
```bash
crontab -e  # Edit and save
```

**Systemd:**
```bash
# Edit timer file
sudo nano /etc/systemd/system/magicmirror-on@weekend.timer

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart magicmirror-on@weekend.timer
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
python3 ~/magicmirror-config/client/pir-control-display/pir.py

# Wave hand in front of sensor
# Display should turn on, then off after 15 minutes of no motion
```

---

## Troubleshooting

### Black Screen with Cursor (Common Issue)

**Symptom:** Display shows black screen with cursor but no MagicMirror

**Solution:**
1. Check logs: `tail -100 ~/magicmirror_start.log`
2. Look for error: "clientonly is not running code null"
3. This has been fixed in the latest version - make sure you've run `git pull`

### MagicMirror Won't Start

```bash
# Test server connectivity (adjust path to your installation)
~/magicmirror-config/client/check_server.sh

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
systemctl status magicmirror-pir.service
```

### View Detailed Error Logs

```bash
# Cron mode
tail -100 ~/magicmirror_start.log
tail -100 /tmp/magicmirror.log

# Systemd mode
journalctl -xeu magicmirror-client.service -n 100
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
│   ├── systemd/               # Systemd service files (optional)
│   │   ├── INSTALL.md
│   │   ├── *.service
│   │   └── *.timer
│   ├── pir-control-display/
│   │   ├── pir.py             # PIR motion sensor script
│   │   └── turn_*_display.sh  # Manual display control
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

Modify in `crontab -e` or systemd timer files.

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
3. Check logs: `tail -f ~/magicmirror_start.log`
4. For systemd: See `client/systemd/INSTALL.md`
