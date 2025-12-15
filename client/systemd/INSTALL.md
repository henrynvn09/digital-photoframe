# Systemd Installation Guide for MagicMirror Client

This guide explains how to migrate from cron-based scheduling to systemd services and timers for more reliable MagicMirror operation.

## Table of Contents
- [Why Systemd?](#why-systemd)
- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
- [Testing](#testing)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Rollback to Cron](#rollback-to-cron)

---

## Why Systemd?

**Benefits over cron:**
- ✅ **Auto-restart on crash** - No more blackouts when MagicMirror crashes
- ✅ **Proper environment** - Automatically inherits graphical session variables
- ✅ **Better logging** - Use `journalctl` to view detailed logs
- ✅ **Service dependencies** - PIR service only runs when MagicMirror runs
- ✅ **Status monitoring** - Easy to check if services are running
- ✅ **Persistent timers** - Missed schedules run after reboot

---

## Prerequisites

1. **Raspberry Pi OS** with systemd (default on modern versions)
2. **MagicMirror** installed at `/home/pi/MagicMirror`
3. **This repository** cloned to `/home/pi/Code/digital-photoframe`
4. **Root/sudo access** for systemd installation

---

## Installation Steps

### Step 1: Stop Existing Cron Jobs (Temporarily)

First, disable cron jobs to prevent conflicts:

```bash
# Edit crontab
crontab -e

# Comment out (add # at start of line) all MagicMirror related cron jobs:
# 0 8 * * 6,0 /bin/bash /home/pi/Code/digital-photoframe/client/turn_on_magic_mirror.sh >> /home/pi/magicmirror_start.log 2>&1
# 45 20 * * 6,0  /bin/bash /home/pi/Code/digital-photoframe/client/turn_off_magic_mirror.sh >> /home/pi/magicmirror_stop.log  2>&1
# 0 16 * * 1-5 /bin/bash /home/pi/Code/digital-photoframe/client/turn_on_magic_mirror.sh >> /home/pi/magicmirror_start.log 2>&1
# 45 20 * * 1-5 /bin/bash /home/pi/Code/digital-photoframe/client/turn_off_magic_mirror.sh >> /home/pi/magicmirror_stop.log  2>&1

# Save and exit
```

**DO NOT DELETE** the cron jobs yet - just comment them out for easy rollback.

### Step 2: Install Systemd Service Files

```bash
# Navigate to the systemd directory
cd ~/Code/digital-photoframe/client/systemd

# Copy service files to systemd directory
sudo cp magicmirror-client.service /etc/systemd/system/
sudo cp magicmirror-pir.service /etc/systemd/system/
sudo cp magicmirror-on@.service /etc/systemd/system/
sudo cp magicmirror-off.service /etc/systemd/system/

# Copy timer files
sudo cp magicmirror-on@weekend.timer /etc/systemd/system/
sudo cp magicmirror-on@weekday.timer /etc/systemd/system/
sudo cp magicmirror-off.timer /etc/systemd/system/

# Reload systemd to recognize new files
sudo systemctl daemon-reload
```

### Step 3: Enable Timers

```bash
# Enable timers (they will start automatically on boot)
sudo systemctl enable magicmirror-on@weekend.timer
sudo systemctl enable magicmirror-on@weekday.timer
sudo systemctl enable magicmirror-off.timer

# Start timers immediately
sudo systemctl start magicmirror-on@weekend.timer
sudo systemctl start magicmirror-on@weekday.timer
sudo systemctl start magicmirror-off.timer
```

### Step 4: Verify Installation

```bash
# Check that all timers are active
systemctl list-timers magicmirror-*

# You should see output like:
# NEXT                         LEFT          LAST PASSED UNIT                              ACTIVATES
# Sat 2025-12-14 08:00:00 PST  17h left      n/a  n/a    magicmirror-on@weekend.timer      magicmirror-on@weekend.service
# Mon 2025-12-16 16:00:00 PST  1 day left    n/a  n/a    magicmirror-on@weekday.timer      magicmirror-on@weekday.service
# Sat 2025-12-14 20:45:00 PST  6h left       n/a  n/a    magicmirror-off.timer             magicmirror-off.service
```

**Important:** The timers are now installed, but MagicMirror won't start until the scheduled time.

---

## Testing

### Manual Testing (Before Relying on Timers)

Test the services manually to ensure they work:

```bash
# Start MagicMirror manually
sudo systemctl start magicmirror-client.service

# Wait 5 seconds, then check status
sleep 5
sudo systemctl status magicmirror-client.service

# If it says "active (running)" - SUCCESS! ✅
# If it says "failed" - see Troubleshooting section below

# Start PIR service
sudo systemctl start magicmirror-pir.service

# Check PIR status
sudo systemctl status magicmirror-pir.service

# Test display with PIR sensor (wave hand in front of sensor)
# Display should turn on after motion detected

# Stop both services
sudo systemctl stop magicmirror-pir.service
sudo systemctl stop magicmirror-client.service
```

### Test Timers

```bash
# Check when next timer will fire
systemctl list-timers magicmirror-*

# To test immediately without waiting for scheduled time:
sudo systemctl start magicmirror-on@weekend.service

# Check if it started successfully
sudo systemctl status magicmirror-client.service
sudo systemctl status magicmirror-pir.service

# Stop it
sudo systemctl start magicmirror-off.service
```

---

## Monitoring

### Check Service Status

```bash
# Quick status check
systemctl status magicmirror-client.service
systemctl status magicmirror-pir.service

# Check if services are running
systemctl is-active magicmirror-client.service
systemctl is-active magicmirror-pir.service

# View timer schedule
systemctl list-timers magicmirror-*
```

### View Logs

```bash
# View MagicMirror client logs (last 50 lines)
journalctl -u magicmirror-client.service -n 50

# View PIR sensor logs
journalctl -u magicmirror-pir.service -n 50

# Follow logs in real-time (like tail -f)
journalctl -fu magicmirror-client.service

# View logs from specific time range
journalctl -u magicmirror-client.service --since "1 hour ago"
journalctl -u magicmirror-client.service --since "2025-12-14 08:00:00"

# View all MagicMirror related logs
journalctl -u magicmirror-* -n 100
```

### Check Auto-Restart Behavior

To verify auto-restart works:

```bash
# Start MagicMirror
sudo systemctl start magicmirror-client.service

# Get the process ID
pgrep -f electron

# Kill it manually to simulate crash
sudo pkill -9 -f electron

# Wait 10 seconds (RestartSec=10s in service file)
sleep 10

# Check if it restarted automatically
systemctl status magicmirror-client.service

# Should show "active (running)" with recent restart timestamp ✅
```

---

## Troubleshooting

### Service Won't Start

**Problem:** `sudo systemctl start magicmirror-client.service` fails

**Solution:**
```bash
# View detailed error logs
journalctl -xeu magicmirror-client.service

# Common issues:
# 1. Server not reachable
#    - Check if NAS is running: ping 192.168.4.45
#    - Check if port is open: nc -zv 192.168.4.45 8036

# 2. Display environment not set
#    - Check if X11 is running: echo $DISPLAY
#    - Try running manually: DISPLAY=:0 ~/Code/digital-photoframe/client/mm.sh

# 3. Permission issues
#    - Check script permissions: ls -l ~/Code/digital-photoframe/client/*.sh
#    - Make executable: chmod +x ~/Code/digital-photoframe/client/*.sh
```

### PIR Service Fails

**Problem:** PIR service won't start

**Solution:**
```bash
# Check logs
journalctl -xeu magicmirror-pir.service

# Common issues:
# 1. GPIO permissions
#    - Add user to gpio group: sudo usermod -a -G gpio pi
#    - Logout and login again

# 2. Python dependencies missing
#    - Install gpiozero: pip3 install gpiozero

# 3. PIR script path wrong
#    - Verify path: ls -l ~/Code/digital-photoframe/client/pir-control-display/pir.py
```

### Timers Not Firing

**Problem:** Scheduled timers don't start services

**Solution:**
```bash
# Check if timers are enabled
systemctl list-timers magicmirror-*

# If not listed, enable them:
sudo systemctl enable magicmirror-on@weekend.timer
sudo systemctl enable magicmirror-on@weekday.timer
sudo systemctl enable magicmirror-off.timer

# Start timers
sudo systemctl start magicmirror-on@weekend.timer
sudo systemctl start magicmirror-on@weekday.timer
sudo systemctl start magicmirror-off.timer

# Verify next run time
systemctl list-timers magicmirror-*
```

### Display Stays Black

**Problem:** Services running but display is black

**Solution:**
```bash
# Check if MagicMirror process is actually running
ps aux | grep electron

# Check display power state
vcgencmd display_power

# If display_power=0, turn it on manually:
vcgencmd display_power 1

# Check PIR sensor is working:
sudo systemctl status magicmirror-pir.service
journalctl -fu magicmirror-pir.service

# Wave hand in front of PIR sensor - should see log entry
```

### Service Keeps Restarting

**Problem:** Service constantly restarting (check with `systemctl status`)

**Solution:**
```bash
# This means MagicMirror is crashing immediately
# Check logs for error messages:
journalctl -xeu magicmirror-client.service -n 100

# Disable auto-restart temporarily to debug:
sudo systemctl stop magicmirror-client.service

# Run manually to see errors:
DISPLAY=:0 ~/Code/digital-photoframe/client/mm.sh

# Common causes:
# - Server unreachable (check network)
# - Config file issue on NAS
# - Display server (X11) not running
```

---

## Rollback to Cron

If systemd isn't working and you want to go back to cron:

### Step 1: Stop and Disable Systemd Services

```bash
# Stop services
sudo systemctl stop magicmirror-client.service
sudo systemctl stop magicmirror-pir.service

# Disable timers
sudo systemctl disable magicmirror-on@weekend.timer
sudo systemctl disable magicmirror-on@weekday.timer
sudo systemctl disable magicmirror-off.timer

# Stop timers
sudo systemctl stop magicmirror-on@weekend.timer
sudo systemctl stop magicmirror-on@weekday.timer
sudo systemctl stop magicmirror-off.timer
```

### Step 2: Re-enable Cron Jobs

```bash
# Edit crontab
crontab -e

# Uncomment (remove # from start of line) the MagicMirror cron jobs
# Save and exit
```

### Step 3: (Optional) Remove Systemd Files

```bash
# Only if you're sure you won't use systemd:
sudo rm /etc/systemd/system/magicmirror-*.service
sudo rm /etc/systemd/system/magicmirror-*.timer
sudo systemctl daemon-reload
```

---

## Advanced Configuration

### Change Schedule Times

To modify when MagicMirror starts/stops:

```bash
# Edit timer file on Raspberry Pi
sudo nano /etc/systemd/system/magicmirror-on@weekend.timer

# Change OnCalendar line:
OnCalendar=Sat,Sun 08:00:00  # Change to desired time

# Save and exit, then reload
sudo systemctl daemon-reload
sudo systemctl restart magicmirror-on@weekend.timer
```

### Add Email Notifications on Failure

```bash
# Edit service file
sudo nano /etc/systemd/system/magicmirror-client.service

# Add under [Service] section:
OnFailure=status-email@%n.service

# Requires mail setup on Pi (not covered here)
```

### Reduce Logging

```bash
# Edit service to reduce log verbosity
sudo nano /etc/systemd/system/magicmirror-client.service

# Change or add:
StandardOutput=null
StandardError=journal

# Reload
sudo systemctl daemon-reload
sudo systemctl restart magicmirror-client.service
```

---

## Quick Reference Commands

```bash
# Start/stop manually
sudo systemctl start magicmirror-client.service
sudo systemctl stop magicmirror-client.service

# Restart
sudo systemctl restart magicmirror-client.service

# View status
systemctl status magicmirror-client.service

# View logs
journalctl -u magicmirror-client.service -n 50
journalctl -fu magicmirror-client.service  # Follow mode

# List timers
systemctl list-timers magicmirror-*

# Enable/disable auto-start
sudo systemctl enable magicmirror-client.service
sudo systemctl disable magicmirror-client.service

# Reload configuration after editing
sudo systemctl daemon-reload
```

---

## Support

If you encounter issues not covered here:

1. **Check logs first:** `journalctl -xeu magicmirror-client.service`
2. **Verify server reachable:** `nc -zv 192.168.4.45 8036`
3. **Test scripts manually:** `~/Code/digital-photoframe/client/mm.sh`
4. **Check file permissions:** `ls -l ~/Code/digital-photoframe/client/*.sh`

For further assistance, check the main README.md or AGENTS.md files.
