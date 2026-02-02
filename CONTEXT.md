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
- [ ] Test on local Mac ↔ VM (kumo-devbox)
- [ ] Push to GitHub

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
