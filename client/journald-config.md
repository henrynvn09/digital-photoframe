# Journald Configuration for Digital Photo Frame

## Overview
This project uses systemd journal for all logging with automatic rotation to prevent disk space issues.

## Configuration File
The setup script automatically creates `/etc/systemd/journald.conf.d/digitalframe.conf` with the following settings:

```ini
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
```

## Manual Configuration

If you need to configure journald manually (without using `setup_client.sh`):

### 1. Create Configuration Directory
```bash
sudo mkdir -p /etc/systemd/journald.conf.d
```

### 2. Create Configuration File
```bash
sudo nano /etc/systemd/journald.conf.d/digitalframe.conf
```

Paste the configuration shown above, then save and exit (Ctrl+X, Y, Enter).

### 3. Restart Journald
```bash
sudo systemctl restart systemd-journald
```

### 4. Verify Settings
```bash
# Check current disk usage
journalctl --disk-usage

# Verify journal integrity
journalctl --verify
```

### 5. Restart Digital Photo Frame Service
```bash
sudo systemctl restart digitalframe.service
```

## Configuration Explained

### SystemMaxUse=64M
- **Purpose**: Limits total disk space used by all persistent journal files
- **Effect**: Once 64MB is reached, oldest logs are automatically deleted
- **Rationale**: Raspberry Pi typically has limited SD card space; 64MB is conservative and prevents any disk space issues while still providing ~1 week of normal operation logs

### SystemMaxFileSize=8M
- **Purpose**: Maximum size for individual journal files before rotation
- **Effect**: Creates up to 8 journal files (~8MB each) totaling 64MB max
- **Rationale**: Smaller files rotate more frequently, preventing large monolithic log files

### RuntimeMaxUse=32M
- **Purpose**: Limits RAM usage for volatile (non-persistent) logs
- **Effect**: Prevents log buffering from consuming too much memory
- **Rationale**: Raspberry Pi 3B has limited RAM (1GB); keep volatile logs minimal

### MaxRetentionSec=3d
- **Purpose**: Automatically deletes journal entries older than 3 days
- **Effect**: Time-based cleanup regardless of disk usage
- **Rationale**: 3 days provides enough history for troubleshooting while preventing unbounded growth

### ForwardToSyslog=no
- **Purpose**: Disables forwarding to traditional syslog
- **Effect**: Avoids duplicate logging and reduces disk I/O
- **Rationale**: Journald is sufficient; no need for duplicate syslog files

## Testing Rotation

Verify that rotation works correctly:

```bash
# 1. Check current usage
journalctl --disk-usage

# 2. Enable debug mode temporarily (generates logs quickly)
nano ~/digital-photoframe/client/schedule.conf
# Set DEBUG=true

# 3. Restart service
sudo systemctl restart digitalframe.service

# 4. Wait 5-10 minutes and check usage again
journalctl --disk-usage

# 5. Disable debug mode
nano ~/digital-photoframe/client/schedule.conf
# Set DEBUG=false

# 6. Restart service
sudo systemctl restart digitalframe.service
```

## Expected Results
- Total journal size stays under 64MB
- Logs older than 3 days automatically deleted
- Individual journal files limited to 8MB (triggers rotation)
- No manual intervention required

## Viewing Logs

### Basic Commands
```bash
# View last 50 lines
journalctl -u digitalframe.service -n 50

# Follow logs in real-time
journalctl -fu digitalframe.service

# View logs from today
journalctl -u digitalframe.service --since today

# View only errors
journalctl -u digitalframe.service -p err

# Check disk usage
journalctl --disk-usage
```

### Manual Cleanup
If you need to manually clean logs (e.g., after debugging):

```bash
# Remove logs older than 3 days
sudo journalctl --vacuum-time=3d

# Limit total size to 64MB
sudo journalctl --vacuum-size=64M

# Limit to specific number of files
sudo journalctl --vacuum-files=8
```

## Troubleshooting

### Logs Still Growing Too Large

**Check configuration is active:**
```bash
# Verify config file exists
cat /etc/systemd/journald.conf.d/digitalframe.conf

# Check if journald loaded the config
sudo systemctl status systemd-journald

# Force journald to reload config
sudo systemctl restart systemd-journald
```

**Immediate cleanup:**
```bash
# Force vacuum to size limit
sudo journalctl --vacuum-size=64M

# Force vacuum to time limit
sudo journalctl --vacuum-time=3d
```

### Journald Restart Fails

**Check for syntax errors:**
```bash
# Verify systemd service
sudo systemd-analyze verify systemd-journald.service

# Check journald logs
journalctl -u systemd-journald -n 50
```

**Common issues:**
- Missing `[Journal]` section header
- Invalid parameter names or values
- File permission issues (should be owned by root)

**Fix permissions if needed:**
```bash
sudo chown root:root /etc/systemd/journald.conf.d/digitalframe.conf
sudo chmod 644 /etc/systemd/journald.conf.d/digitalframe.conf
```

### Journal Integrity Issues

**Check journal health:**
```bash
# Verify journal files
journalctl --verify

# If corruption detected, rotate journals
sudo journalctl --rotate
sudo journalctl --vacuum-time=1d
```

### Debug Mode Consuming Too Much Space

If you enabled DEBUG=true and forgot to disable it:

```bash
# 1. Immediately disable debug mode
nano ~/digital-photoframe/client/schedule.conf
# Set DEBUG=false

# 2. Restart service
sudo systemctl restart digitalframe.service

# 3. Clean old debug logs
sudo journalctl --vacuum-time=1h  # Keep only last hour

# 4. Verify disk usage
journalctl --disk-usage
```

## Adjusting Limits

If 64MB / 3 days is not appropriate for your use case:

### Increase Limits (More History)
```bash
sudo nano /etc/systemd/journald.conf.d/digitalframe.conf
```

Change to:
```ini
SystemMaxUse=64M       # 64MB total
SystemMaxFileSize=8M   # 64MB per file
MaxRetentionSec=7d     # 7 days retention
```

Then restart:
```bash
sudo systemctl restart systemd-journald
```

### Decrease Limits (Save More Space)
```bash
sudo nano /etc/systemd/journald.conf.d/digitalframe.conf
```

Change to:
```ini
SystemMaxUse=4M        # 4MB total
SystemMaxFileSize=1M   # 1MB per file
MaxRetentionSec=1d     # 1 day retention
```

Then restart:
```bash
sudo systemctl restart systemd-journald
```

## Monitoring

Set up a simple monitoring script (optional):

```bash
# Create monitoring script
cat > ~/check_logs.sh << 'EOF'
#!/bin/bash
MAX_SIZE_MB=64
current_size=$(journalctl --disk-usage | grep -oP 'currently use \K[0-9.]+(?=M)')
if (( $(echo "$current_size > $MAX_SIZE_MB" | bc -l) )); then
    echo "WARNING: Journal size ${current_size}MB exceeds ${MAX_SIZE_MB}MB limit"
    journalctl --disk-usage
else
    echo "OK: Journal size ${current_size}MB (limit: ${MAX_SIZE_MB}MB)"
fi
EOF

chmod +x ~/check_logs.sh

# Run it manually or add to cron
./check_logs.sh
```

## System-Wide vs. Service-Specific

**Note**: This configuration affects **all systemd services** on the system, not just `digitalframe.service`.

If you want service-specific limits, use `RateLimitIntervalSec` and `RateLimitBurst` in the service file instead:

```ini
[Service]
# Limit to 1000 messages per 30 seconds
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000
```

However, for most single-purpose Raspberry Pi setups (like this digital photo frame), system-wide limits are simpler and sufficient.

## Further Reading

- [systemd.journald man page](https://www.freedesktop.org/software/systemd/man/journald.conf.html)
- [journalctl man page](https://www.freedesktop.org/software/systemd/man/journalctl.html)
- [Arch Linux Wiki: Systemd/Journal](https://wiki.archlinux.org/title/Systemd/Journal)
