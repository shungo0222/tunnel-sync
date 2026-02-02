# tunnel-sync Architecture

A simplified overview of how tunnel-sync works.

## What It Does

Creates a shared folder between your Mac and a remote VM. Files you put in the folder appear on both machines.

```
Your Mac                          Remote VM
────────                          ─────────
~/tunnel-share/                   ~/tunnel-share/
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
2. Move to `~/tunnel-share/`
3. Paste (path auto-copied to clipboard)
4. Claude can see it

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   1. You drop a file into ~/tunnel-share/                   │
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

## Sync Direction

| Action | Result |
|--------|--------|
| Add file locally | → Appears on VM, path copied to clipboard |
| Add file on VM | → Appears locally (periodic sync) |
| Delete locally | → Deleted on VM |
| Delete on VM | → Deleted locally |

## Configuration

Edit `~/.tunnel-sync.conf`:

```bash
REMOTE_HOST="kumo"              # Your VM's SSH alias
REMOTE_DIR="~/tunnel-share"     # Folder on VM
LOCAL_DIR="$HOME/tunnel-share"  # Folder on Mac
```

## Quick Start

```bash
# Install
./install.sh

# Start
tunnel-sync start

# Use it
mv ~/Desktop/screenshot.png ~/tunnel-share/
# Path is now in your clipboard!

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
