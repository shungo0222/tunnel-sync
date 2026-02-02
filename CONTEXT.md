# CONTEXT — tunnel-sync

This file contains the background, context, and progress log for the tunnel-sync project. It should be read by AI assistants (Claude Code, etc.) to understand the full history and intent of this project.

---

## 1) Background and Problem Statement

### The Situation

- A developer works on a remote VM (GCP) via SSH/Tailscale
- Claude Code runs on the remote VM for development work
- When debugging issues (Firestore errors, GCP console logs, UI bugs), screenshots are extremely helpful
- On local machine, screenshots can be drag-and-dropped into Claude Code easily
- **Problem**: When Claude Code runs on a remote VM, local screenshots cannot be directly shared

### The Challenge

When you take a screenshot on your local Mac and try to share it with Claude Code running on a remote VM:
1. The screenshot is saved locally (e.g., `~/Desktop/Screenshot.png`)
2. If you drag-and-drop it into the terminal, it inserts the **local path**
3. The remote Claude Code cannot access `/Users/yourname/Desktop/Screenshot.png` because it's a different filesystem

### Research Conducted (2026-02-02)

Investigated multiple solutions:
- **claude-screenshot-uploader**: Auto-uploads all screenshots (privacy concern)
- **Claudeboard VS Code extension**: Requires VS Code
- **tfLink**: External service dependency
- **Manual scp/rsync**: Works but tedious

**Conclusion**: Need a custom solution that:
- Syncs only a **specific folder** (not all screenshots)
- Provides **bidirectional sync** (local ↔ VM)
- **Automatically copies the VM path** to clipboard when files are added locally

---

## 2) Requirements and Specifications

### Core Requirements

1. **Selective Sync**: Only files in a designated folder are synced (privacy-conscious)
2. **Bidirectional Sync**:
   - Add file locally → appears on VM
   - Add file on VM → appears locally
   - Delete from either side → deleted on both
3. **Automatic Clipboard**: When a file is added to the local folder, the VM-accessible path is copied to clipboard
4. **Configurable Paths**: Both local and remote folder paths should be configurable via a config file
5. **No Secrets in Code**: Safe for public repository

### User Workflow

```
1. User takes screenshot (Cmd+Shift+4) → saved to ~/Desktop
2. User moves screenshot to ~/tunnel-share (the designated sync folder)
3. tunnel-sync detects the new file
4. File is synced to VM's ~/tunnel-share
5. VM path (e.g., ~/tunnel-share/screenshot.png) is copied to clipboard
6. User pastes into remote Claude Code session → Claude can read the image
```

### Technical Decisions

- **Sync Tool**: rsync with fswatch for monitoring (simpler) OR unison/mutagen (true bidirectional)
- **Clipboard**: macOS `pbcopy` for copying paths
- **Config Format**: Shell script or YAML/JSON
- **Daemon**: Optional background service via launchd

---

## 3) Project Structure

```
tunnel-sync/
├── README.md              # Detailed technical specification
├── ARCHITECTURE.md        # Simplified human-readable overview
├── CONTEXT.md             # This file - history and context
├── config.example.sh      # Example configuration file
├── tunnel-sync.sh         # Main sync script
├── install.sh             # Installation script
├── uninstall.sh           # Uninstallation script
└── .gitignore
```

---

## 4) Progress Log

### 2026-02-02: Project Initialization

- [x] Created project folder: `~/Programming/tunnel-sync`
- [x] Initialized git repository
- [x] Created CONTEXT.md with background and requirements
- [x] Created README.md with technical specifications (including system diagrams)
- [x] Created ARCHITECTURE.md with simplified overview
- [x] Created config.example.sh with all configurable options
- [x] Implemented tunnel-sync.sh (main script with watch, push, pull, sync, start, stop commands)
- [x] Implemented install.sh (dependency installation, config setup, launchd service)
- [x] Implemented uninstall.sh (clean removal)
- [x] Created .gitignore
- [x] Made scripts executable
- [x] Pushed to GitHub (initial commit)

### 2026-02-02: Installation and Testing

- [x] Installed fswatch via Homebrew
- [x] Created config file with REMOTE_HOST="kumo"
- [x] Created local sync folder: ~/tunnel-share
- [x] Created remote sync folder: ~/tunnel-share on VM
- [x] Installed tunnel-sync to ~/.local/bin/
- [x] Fixed bash compatibility issue (macOS uses bash 3.x, removed `declare -A`)
- [x] Tested local → VM sync: ✅ Working
- [x] Tested clipboard auto-copy: ✅ Working
- [x] Tested VM → local sync (pull): ✅ Working
- [x] Committed and pushed fixes

### 2026-02-02: Infinite Loop Bug Fix (v1.1.0)

**Problem Discovered**: Bidirectional sync caused infinite loop
- Local change detected → sync to VM
- Periodic pull from VM → local files updated
- Local change detected again → sync to VM
- Repeat forever (notifications spam)

**Solution Implemented**: Lock file mechanism
- `LOCK_FILE="$HOME/.tunnel-sync.lock"` created during sync
- `watch_and_sync()` skips events when lock file exists
- Lock held for 1-2 seconds after sync to let fswatch events settle
- Added `--latency 1` to fswatch for better debouncing
- Increased `SYNC_INTERVAL` from 5s to 30s to reduce pull frequency

**Changes in v1.1.0**:
- Added lock file functions: `acquire_lock()`, `release_lock()`, `is_locked()`
- Modified `sync_to_remote()` and `sync_from_remote()` to use locks
- Modified `watch_and_sync()` to skip events during sync
- Added cleanup of lock file in `stop_daemon()` and `start_daemon()`
- Added trap for clean exit in `run_daemon()`
- Better child process cleanup with `pkill -P`
- Added sync interval display in `status` command

### 2026-02-02: Additional Fixes (v1.2.0)

**Problem 1**: Lock mechanism alone wasn't enough - events still fired after lock release

**Solution**: Added cooldown period
- `LAST_SYNC_FILE` records timestamp of last sync completion
- `seconds_since_last_sync()` checks elapsed time
- Events within 5 seconds of last sync are skipped
- Increased fswatch `--latency` to 2 seconds

**Problem 2**: `--delete` in `sync_from_remote()` was deleting newly created local files

**Scenario**:
1. User creates file locally
2. Before sync_to_remote completes, sync_from_remote runs
3. VM doesn't have the file yet
4. `--delete` removes the local file

**Solution**: Removed `--delete` from `sync_from_remote()`
- Files created on VM will be pulled to local
- Files deleted on VM will remain locally (manual cleanup needed)
- This is safer for the primary use case (local → VM sync)

**Final Test Results** (v1.2.0):
- ✅ File added locally → synced to VM
- ✅ Clipboard auto-copied with VM path
- ✅ No infinite loop
- ✅ No accidental file deletion

### 2026-02-02: Auto-Start Configuration

**Setup**: macOS launchd service for automatic startup on login

**Location**: `~/Library/LaunchAgents/com.tunnelsync.daemon.plist`

**Configuration**:
```xml
- Label: com.tunnelsync.daemon
- ProgramArguments: /bin/bash tunnel-sync.sh _daemon
- RunAtLoad: true
- KeepAlive: true (restarts if crashes)
- Logs: ~/.tunnel-sync.log
```

**Design Decisions**:

1. **VM auto-start not needed**: tunnel-sync runs only on local Mac, manages both push and pull

2. **Not included in chezmoi/dotfiles**:
   - tunnel-sync is workflow-specific (remote VM development)
   - Not needed on all machines
   - Requires machine-specific config (~/.tunnel-sync.conf)
   - Should be consciously installed by user

3. **Machine-specific files** (not in dotfiles):
   - `~/.tunnel-sync.conf` - remote host configuration
   - `~/Library/LaunchAgents/com.tunnelsync.daemon.plist` - launchd service
   - `~/tunnel-share/` - sync folder

**Commands**:
```bash
# Check status
launchctl list | grep tunnel

# Stop service
launchctl unload ~/Library/LaunchAgents/com.tunnelsync.daemon.plist

# Start service
launchctl load ~/Library/LaunchAgents/com.tunnelsync.daemon.plist

# Manual control (if launchd not used)
~/.local/bin/tunnel-sync start
~/.local/bin/tunnel-sync stop
```

### 2026-02-02: Version 2.0.0 - Maintenance Features

**New Features Added**:

1. **Log Rotation** (`rotate_logs()`)
   - Automatically rotates logs when file exceeds `MAX_LOG_SIZE_MB`
   - Keeps one backup file (`.log.old`)
   - Runs on daemon startup

2. **Health Check** (`tunnel-sync health`)
   - Comprehensive diagnostic command
   - Checks: daemon status, local/remote directories, SSH connectivity, fswatch monitoring, log file, config file
   - Shows ✅/❌ status indicators
   - Returns exit code 0 (healthy) or 1 (issues)

3. **Auto-Cleanup** (`cleanup_old_files()`)
   - Deletes files older than `AUTO_CLEANUP_DAYS` (default: 7)
   - Can be run manually: `tunnel-sync cleanup [days]`
   - Runs automatically on daemon start if `CLEANUP_ON_START=true`
   - Daily scheduled cleanup in background

4. **Logs Viewer** (`tunnel-sync logs [lines]`)
   - View recent log entries without remembering log path
   - Default: last 50 lines

**New Configuration Options**:
```bash
MAX_LOG_SIZE_MB=10      # Log rotation threshold
AUTO_CLEANUP_DAYS=7     # Auto-delete files older than N days (0 to disable)
CLEANUP_ON_START=true   # Run cleanup when daemon starts
```

**Updated Commands**:
```bash
tunnel-sync health      # Run comprehensive diagnostic
tunnel-sync cleanup     # Remove files older than AUTO_CLEANUP_DAYS
tunnel-sync cleanup 3   # Remove files older than 3 days
tunnel-sync logs        # Show last 50 log entries
tunnel-sync logs 100    # Show last 100 log entries
```

**Sync Folder Location Change**:
- Changed default LOCAL_DIR from `~/tunnel-share` to `~/Desktop/tunnel-share`
- More convenient location for drag-and-drop workflow

---

## 5) Environment Information

### Local Machine
- **OS**: macOS
- **Terminal**: iTerm2
- **SSH**: Tailscale SSH to VM

### Remote VM (kumo-devbox)
- **Provider**: GCP
- **OS**: Ubuntu 24.04 LTS
- **IP**: 100.100.142.79 (Tailscale)
- **SSH Alias**: `kumo`
- **User**: pochi

### Connection
- Tailscale VPN connects local Mac, VM, and iPhone
- SSH works via `ssh kumo` (no password/key needed with Tailscale SSH)

---

## 6) Design Decisions

### Why Selective Sync (Not Auto-Upload All Screenshots)?

**Privacy**: Users may take screenshots containing sensitive information they don't want on the VM. By requiring explicit action (moving to sync folder), users maintain control over what is shared.

### Why Bidirectional Sync?

Sometimes you may want to:
- Download logs or outputs from VM to local
- Share files from VM to local for further processing
- Keep both sides in sync without manual intervention

### Why Clipboard Auto-Copy?

The main use case is sharing files with remote Claude Code. After moving a file to the sync folder, you want to immediately paste the path. Copying to clipboard eliminates the need to remember or type the remote path.

---

## 7) Related Projects

This project is part of the **KumoShogun** ecosystem:
- **kumo-shogun**: Main project for AI-driven development on remote VM
- **tunnel-sync**: This project - file sharing between local and VM

---

## 8) Future Considerations

- Support for multiple sync folders
- Integration with macOS Finder (right-click "Send to VM")
- iOS Shortcuts support for syncing from iPhone
- Compression for large files
- Conflict resolution UI
