# tunnel-sync

Bidirectional file sync between local machine and remote VM with automatic clipboard path copy.

**Version**: 2.0.0

## Overview

tunnel-sync creates a "tunnel" between a folder on your local machine and a folder on a remote VM. Files added to either side are automatically synced to the other. When you add a file locally, the remote path is automatically copied to your clipboard for easy pasting into remote terminal sessions.

## Features

- **Bidirectional Sync**: Changes on either side are reflected on both
- **Selective Sharing**: Only syncs files you explicitly place in the tunnel folder
- **Clipboard Integration**: Automatically copies remote path when local files are added
- **Configurable**: Set your own local and remote folder paths
- **Lightweight**: Uses standard tools (rsync, fswatch, ssh)
- **Privacy-Conscious**: You control exactly what gets shared
- **Log Rotation**: Automatic log rotation when file exceeds configurable size
- **Auto-Cleanup**: Automatically removes files older than N days
- **Health Check**: Built-in diagnostic command to verify all components

## Use Case

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Primary Use Case: Share screenshots with remote Claude Code            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. Take screenshot on Mac (Cmd+Shift+4)                                │
│  2. Move to tunnel folder (e.g., ~/tunnel-share)                        │
│  3. tunnel-sync detects and uploads to VM                               │
│  4. Remote path copied to clipboard                                     │
│  5. Paste into remote Claude Code → image is analyzed                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## System Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        tunnel-sync Architecture                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   LOCAL MACHINE (macOS)                 REMOTE VM (Linux)                │
│   ─────────────────────                 ───────────────────              │
│                                                                          │
│   ~/tunnel-share/                       ~/tunnel-share/                  │
│   ├── screenshot.png     ◄── rsync ──► ├── screenshot.png               │
│   ├── error-log.txt      ◄── SSH ────► ├── error-log.txt                │
│   └── design.jpg         ◄───────────► └── design.jpg                   │
│                                                                          │
│   ┌─────────────────┐                                                    │
│   │    fswatch      │ ─── detects new file                               │
│   │   (monitor)     │                                                    │
│   └────────┬────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │  tunnel-sync.sh │                                                    │
│   │                 │ ─── 1. rsync to VM                                 │
│   │                 │ ─── 2. copy remote path to clipboard               │
│   └─────────────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │    pbcopy       │ ─── "~/tunnel-share/screenshot.png"                │
│   │  (clipboard)    │                                                    │
│   └─────────────────┘                                                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Sync Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Sync Flow                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  LOCAL → REMOTE (Primary Use Case)                                      │
│  ─────────────────────────────────                                      │
│                                                                         │
│  [User Action]          [tunnel-sync]           [Result]                │
│       │                      │                      │                   │
│       │  Move file to        │                      │                   │
│       │  ~/tunnel-share/     │                      │                   │
│       │─────────────────────►│                      │                   │
│       │                      │  fswatch detects     │                   │
│       │                      │  new file            │                   │
│       │                      │──────────────────────┤                   │
│       │                      │  rsync to VM         │                   │
│       │                      │─────────────────────►│                   │
│       │                      │  copy path to        │                   │
│       │                      │  clipboard           │                   │
│       │                      │◄─────────────────────│                   │
│       │  Paste in remote     │                      │                   │
│       │  terminal (Cmd+V)    │                      │  File accessible  │
│       │─────────────────────────────────────────────►  on VM            │
│                                                                         │
│  REMOTE → LOCAL (Reverse Sync)                                          │
│  ─────────────────────────────                                          │
│                                                                         │
│  [VM Action]            [tunnel-sync]           [Result]                │
│       │                      │                      │                   │
│       │  Add file to         │                      │                   │
│       │  ~/tunnel-share/     │                      │                   │
│       │─────────────────────►│                      │                   │
│       │                      │  Periodic sync       │                   │
│       │                      │  pulls from VM       │                   │
│       │                      │──────────────────────┤                   │
│       │                      │                      │  File appears     │
│       │                      │◄─────────────────────│  locally          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Requirements

### Local Machine (macOS)

- macOS 10.15+
- Homebrew (for installing dependencies)
- SSH access to remote VM (key-based or Tailscale SSH)

### Remote VM (Linux)

- rsync installed
- SSH server running
- Writable directory for sync folder

### Dependencies

```bash
# Installed automatically by install.sh
brew install fswatch    # File system monitoring
brew install rsync      # File synchronization (macOS has old version)
```

## Installation

### Quick Install

```bash
git clone https://github.com/YOUR_USERNAME/tunnel-sync.git
cd tunnel-sync
./install.sh
```

### Manual Install

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tunnel-sync.git
   cd tunnel-sync
   ```

2. Copy and edit the config file:
   ```bash
   cp config.example.sh ~/.tunnel-sync.conf
   nano ~/.tunnel-sync.conf
   ```

3. Install dependencies:
   ```bash
   brew install fswatch rsync
   ```

4. Create local sync folder:
   ```bash
   mkdir -p ~/tunnel-share
   ```

5. Create remote sync folder:
   ```bash
   ssh YOUR_VM "mkdir -p ~/tunnel-share"
   ```

6. Add to PATH (optional):
   ```bash
   ln -s $(pwd)/tunnel-sync.sh /usr/local/bin/tunnel-sync
   ```

## Configuration

Configuration file: `~/.tunnel-sync.conf`

```bash
# Remote VM settings
REMOTE_HOST="your-vm-hostname"    # SSH host (e.g., "kumo" or "user@192.168.1.100")
REMOTE_USER=""                     # SSH user (leave empty if included in REMOTE_HOST)
REMOTE_DIR="~/tunnel-share"        # Remote sync directory

# Local settings
LOCAL_DIR="$HOME/tunnel-share"     # Local sync directory

# Sync settings
SYNC_INTERVAL=5                    # Seconds between sync checks (for bidirectional)
EXCLUDE_PATTERNS=".DS_Store,*.tmp,*.swp"  # Files to exclude from sync

# Clipboard settings
COPY_TO_CLIPBOARD=true             # Copy remote path to clipboard on local file add

# Notification settings
SHOW_NOTIFICATIONS=true            # Show macOS notifications on sync

# Logging
LOG_FILE="$HOME/.tunnel-sync.log"  # Log file location
LOG_LEVEL="INFO"                   # DEBUG, INFO, WARN, ERROR
MAX_LOG_SIZE_MB=10                 # Log rotation threshold (MB)

# Auto-cleanup
AUTO_CLEANUP_DAYS=7                # Delete files older than N days (0 to disable)
CLEANUP_ON_START=true              # Run cleanup when daemon starts
```

## Usage

### Start Sync Daemon

```bash
# Start monitoring and syncing
tunnel-sync start

# Or run in foreground (for debugging)
tunnel-sync watch
```

### Manual Sync

```bash
# Sync local → remote
tunnel-sync push

# Sync remote → local
tunnel-sync pull

# Bidirectional sync
tunnel-sync sync
```

### Stop Daemon

```bash
tunnel-sync stop
```

### Check Status

```bash
tunnel-sync status
```

### Health Check

Run a comprehensive diagnostic:

```bash
tunnel-sync health
```

This checks:
- Daemon running status
- Local directory exists
- SSH connectivity
- Remote directory exists
- fswatch monitoring
- Log file status
- Config file presence

### View Logs

```bash
# Show last 50 log entries (default)
tunnel-sync logs

# Show last 100 entries
tunnel-sync logs 100
```

### Cleanup Old Files

```bash
# Remove files older than AUTO_CLEANUP_DAYS (default: 7)
tunnel-sync cleanup

# Remove files older than 3 days
tunnel-sync cleanup 3
```

## Workflow Example

### Sharing a Screenshot with Remote Claude Code

1. **Take screenshot**:
   ```
   Cmd + Shift + 4 (select area)
   → Screenshot saved to ~/Desktop/Screenshot 2026-02-02.png
   ```

2. **Move to tunnel folder**:
   ```bash
   mv ~/Desktop/Screenshot*.png ~/tunnel-share/
   ```

3. **Automatic sync happens**:
   ```
   [tunnel-sync] Syncing: Screenshot 2026-02-02.png
   [tunnel-sync] Copied to clipboard: ~/tunnel-share/Screenshot 2026-02-02.png
   ```

4. **In remote terminal (SSH to VM)**:
   ```
   $ claude
   > (Cmd+V to paste path)
   > Please analyze this screenshot: ~/tunnel-share/Screenshot 2026-02-02.png
   ```

5. **Claude Code reads the image and responds**.

## File Structure

```
tunnel-sync/
├── README.md              # This file - detailed technical specification
├── ARCHITECTURE.md        # Simplified human-readable overview
├── CONTEXT.md             # Project history and context for AI assistants
├── config.example.sh      # Example configuration file
├── tunnel-sync.sh         # Main sync script
├── install.sh             # Installation script
├── uninstall.sh           # Uninstallation script
├── com.tunnelsync.plist   # macOS launchd service definition
└── .gitignore             # Git ignore patterns
```

## Technical Details

### File Monitoring

Uses `fswatch` to monitor the local sync directory for changes:
- New files trigger immediate sync + clipboard copy
- Modified files trigger sync
- Deleted files trigger sync (deletion propagates)

### Sync Mechanism

Uses `rsync` with the following flags:
```bash
rsync -avz --delete --exclude='.DS_Store' LOCAL_DIR/ REMOTE:REMOTE_DIR/
```

- `-a`: Archive mode (preserves permissions, timestamps)
- `-v`: Verbose output
- `-z`: Compress during transfer
- `--delete`: Remove files on destination that don't exist on source
- `--exclude`: Skip specified patterns

### Clipboard Integration

On macOS, uses `pbcopy` to copy the remote path:
```bash
echo "~/tunnel-share/filename.png" | pbcopy
```

### Bidirectional Sync Strategy

1. **Local changes** (via fswatch): Immediate push to remote
2. **Remote changes** (via periodic pull): Pull every N seconds
3. **Conflict resolution**: Last write wins (rsync default)

## Troubleshooting

### Quick Diagnostic

Run the built-in health check:

```bash
tunnel-sync health
```

This will show the status of all components with ✅ or ❌ indicators.

### Sync not working

1. Run health check first:
   ```bash
   tunnel-sync health
   ```

2. Check SSH connection:
   ```bash
   ssh YOUR_VM "echo connected"
   ```

3. Check rsync:
   ```bash
   rsync --version
   ```

4. Check fswatch:
   ```bash
   fswatch --version
   ```

5. Check logs:
   ```bash
   tunnel-sync logs
   # or
   tail -f ~/.tunnel-sync.log
   ```

### Clipboard not working

Ensure you're running from a terminal with clipboard access (not a headless SSH session).

### Permission denied

Ensure remote directory is writable:
```bash
ssh YOUR_VM "touch ~/tunnel-share/test && rm ~/tunnel-share/test"
```

## Security Considerations

- **SSH Key Authentication**: Recommended over password auth
- **Tailscale SSH**: Provides secure, zero-config SSH
- **No Secrets in Repo**: Config file with credentials is in `.gitignore`
- **Selective Sync**: Only explicitly shared files are synced

## Uninstallation

```bash
./uninstall.sh
```

Or manually:
```bash
# Stop daemon
tunnel-sync stop

# Remove launchd service
launchctl unload ~/Library/LaunchAgents/com.tunnelsync.plist
rm ~/Library/LaunchAgents/com.tunnelsync.plist

# Remove config
rm ~/.tunnel-sync.conf

# Remove sync folders (optional - will delete synced files!)
rm -rf ~/tunnel-share
ssh YOUR_VM "rm -rf ~/tunnel-share"
```

## License

MIT License

## Contributing

Contributions welcome! Please read CONTEXT.md to understand the project background before contributing.
