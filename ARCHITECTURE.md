# tunnel-sync Architecture

A simplified overview of how tunnel-sync works.

**Version**: 2.0.0

## What It Does

Creates a shared folder between your Mac and a remote VM. Files you put in the folder appear on both machines.

```
Your Mac                          Remote VM
────────                          ─────────
~/Desktop/tunnel-share/           ~/tunnel-share/
     │                                 │
     └──────────── SYNCED ─────────────┘
```

## The Problem It Solves

**Scenario**: You're coding on a remote VM using Claude Code. You see an error in the browser and want to show Claude a screenshot.

**Without tunnel-sync**:
1. Take screenshot
2. Manually upload via scp
3. Type the remote path
4. Claude can see it

**With tunnel-sync**:
1. Take screenshot
2. Move to `~/Desktop/tunnel-share/`
3. Paste (path auto-copied to clipboard)
4. Claude can see it

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   1. You drop a file into ~/Desktop/tunnel-share/            │
│                        │                                    │
│                        ▼                                    │
│   2. fswatch detects the new file                           │
│                        │                                    │
│                        ▼                                    │
│   3. rsync uploads it to VM                                 │
│                        │                                    │
│                        ▼                                    │
│   4. Remote path copied to clipboard                        │
│                        │                                    │
│                        ▼                                    │
│   5. You paste in remote terminal → Claude reads the file   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| `fswatch` | Watches folder for changes |
| `rsync` | Syncs files over SSH |
| `pbcopy` | Copies path to clipboard |
| `launchd` | Keeps it running in background |

## Maintenance Features (v2.0.0)

| Feature | Purpose |
|---------|---------|
| Log rotation | Automatically rotates logs when they exceed MAX_LOG_SIZE_MB |
| Auto-cleanup | Deletes files older than AUTO_CLEANUP_DAYS |
| Health check | `tunnel-sync health` diagnoses all components |
| Logs viewer | `tunnel-sync logs` shows recent log entries |

## Sync Direction

| Action | Result |
|--------|--------|
| Add file locally | → Appears on VM, remote path(s) copied to clipboard |
| Add file on VM | → Appears locally (periodic sync) |
| Delete locally | → Deleted on VM |
| Delete on VM | → Deleted locally |

## Configuration

Edit `~/.tunnel-sync.conf`:

```bash
REMOTE_HOST="cloudlab"          # Your VM's SSH alias
REMOTE_DIR="~/tunnel-share"     # Folder on VM
LOCAL_DIR="$HOME/Desktop/tunnel-share"  # Folder on Mac
```

## Quick Start

```bash
# Install
./install.sh

# Start
tunnel-sync start

# Use it
mv ~/Desktop/screenshot.png ~/Desktop/tunnel-share/
# Path is now in your clipboard!

# Check status
tunnel-sync health

# View logs
tunnel-sync logs

# Clean up old files
tunnel-sync cleanup

# Stop
tunnel-sync stop
```

## Why This Design?

### Privacy First

Only files you explicitly put in the folder are synced. Your other screenshots stay private.

### Simple Tools

Uses battle-tested Unix tools (rsync, ssh) instead of complex sync services.

### Works Offline

Once set up, works entirely over your local network (Tailscale). No cloud services involved.

## Security

- Files travel over SSH (encrypted)
- No external services or accounts needed
- Config file with paths is local-only (not in git)
