#!/bin/bash

# tunnel-sync uninstaller

set -e

INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.tunnelsync.daemon.plist"
CONFIG_FILE="$HOME/.tunnel-sync.conf"
LOG_FILE="$HOME/.tunnel-sync.log"
PID_FILE="$HOME/.tunnel-sync.pid"
LOCAL_DIR="$HOME/tunnel-share"

echo "================================"
echo "  tunnel-sync Uninstaller"
echo "================================"
echo ""

# Stop daemon if running
echo "1. Stopping daemon..."
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        echo "   ✓ Stopped daemon (PID: $pid)"
    fi
    rm -f "$PID_FILE"
fi

# Unload launchd service
echo ""
echo "2. Removing auto-start service..."
if [[ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]]; then
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "   ✓ Removed launchd service"
else
    echo "   - No launchd service found"
fi

# Remove symlink
echo ""
echo "3. Removing tunnel-sync command..."
if [[ -L "$INSTALL_DIR/tunnel-sync" ]]; then
    if [[ -w "$INSTALL_DIR" ]]; then
        rm -f "$INSTALL_DIR/tunnel-sync"
    else
        sudo rm -f "$INSTALL_DIR/tunnel-sync"
    fi
    echo "   ✓ Removed: $INSTALL_DIR/tunnel-sync"
else
    echo "   - Command not found in $INSTALL_DIR"
fi

# Config file
echo ""
echo "4. Configuration file..."
if [[ -f "$CONFIG_FILE" ]]; then
    read -p "   Remove config file? ($CONFIG_FILE) (y/N): " remove_config
    if [[ "$remove_config" == "y" || "$remove_config" == "Y" ]]; then
        rm -f "$CONFIG_FILE"
        echo "   ✓ Removed config file"
    else
        echo "   - Kept config file"
    fi
else
    echo "   - No config file found"
fi

# Log file
echo ""
echo "5. Log file..."
if [[ -f "$LOG_FILE" ]]; then
    read -p "   Remove log file? ($LOG_FILE) (y/N): " remove_log
    if [[ "$remove_log" == "y" || "$remove_log" == "Y" ]]; then
        rm -f "$LOG_FILE"
        echo "   ✓ Removed log file"
    else
        echo "   - Kept log file"
    fi
else
    echo "   - No log file found"
fi

# Local sync directory
echo ""
echo "6. Local sync directory..."
if [[ -d "$LOCAL_DIR" ]]; then
    file_count=$(ls -1 "$LOCAL_DIR" 2>/dev/null | wc -l | tr -d ' ')
    echo "   Directory: $LOCAL_DIR"
    echo "   Contains: $file_count files"
    read -p "   Remove sync directory and all files? (y/N): " remove_dir
    if [[ "$remove_dir" == "y" || "$remove_dir" == "Y" ]]; then
        rm -rf "$LOCAL_DIR"
        echo "   ✓ Removed sync directory"
    else
        echo "   - Kept sync directory"
    fi
else
    echo "   - No sync directory found"
fi

# Note about remote
echo ""
echo "================================"
echo "  Uninstallation Complete!"
echo "================================"
echo ""
echo "Note: Files on your remote VM were NOT removed."
echo "To remove them manually, run:"
echo "  ssh YOUR_VM 'rm -rf ~/tunnel-share'"
echo ""
echo "To reinstall tunnel-sync:"
echo "  ./install.sh"
