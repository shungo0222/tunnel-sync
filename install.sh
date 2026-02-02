#!/bin/bash

# tunnel-sync installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.tunnel-sync.conf"
INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.tunnelsync.daemon.plist"

echo "================================"
echo "  tunnel-sync Installer"
echo "================================"
echo ""

# Check OS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This installer is for macOS only."
    exit 1
fi

# Install dependencies
echo "1. Checking dependencies..."

if ! command -v brew &> /dev/null; then
    echo "   Error: Homebrew is required. Install from https://brew.sh"
    exit 1
fi

if ! command -v fswatch &> /dev/null; then
    echo "   Installing fswatch..."
    brew install fswatch
else
    echo "   ✓ fswatch is installed"
fi

# Check rsync version (macOS has old version)
rsync_version=$(rsync --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ $(echo "$rsync_version < 3.0" | bc) -eq 1 ]]; then
    echo "   Installing newer rsync..."
    brew install rsync
else
    echo "   ✓ rsync is up to date"
fi

# Create config file
echo ""
echo "2. Setting up configuration..."

if [[ -f "$CONFIG_FILE" ]]; then
    echo "   Config file already exists: $CONFIG_FILE"
    read -p "   Overwrite? (y/N): " overwrite
    if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
        echo "   Keeping existing config"
    else
        cp "$SCRIPT_DIR/config.example.sh" "$CONFIG_FILE"
        echo "   ✓ Created config file: $CONFIG_FILE"
    fi
else
    cp "$SCRIPT_DIR/config.example.sh" "$CONFIG_FILE"
    echo "   ✓ Created config file: $CONFIG_FILE"
fi

# Get remote host configuration
echo ""
echo "3. Remote host configuration..."
read -p "   Enter your VM's SSH host (e.g., kumo or user@ip): " remote_host

if [[ -n "$remote_host" ]]; then
    sed -i '' "s/REMOTE_HOST=\"your-vm-hostname\"/REMOTE_HOST=\"$remote_host\"/" "$CONFIG_FILE"
    echo "   ✓ Set REMOTE_HOST to: $remote_host"
fi

# Create local sync directory
echo ""
echo "4. Creating local sync directory..."

LOCAL_DIR="$HOME/tunnel-share"
mkdir -p "$LOCAL_DIR"
echo "   ✓ Created: $LOCAL_DIR"

# Create remote sync directory
echo ""
echo "5. Creating remote sync directory..."

if [[ -n "$remote_host" ]]; then
    if ssh "$remote_host" "mkdir -p ~/tunnel-share" 2>/dev/null; then
        echo "   ✓ Created: ~/tunnel-share on $remote_host"
    else
        echo "   ⚠ Could not create remote directory. Create it manually:"
        echo "     ssh $remote_host 'mkdir -p ~/tunnel-share'"
    fi
else
    echo "   ⚠ Skipped (no remote host configured)"
fi

# Install script
echo ""
echo "6. Installing tunnel-sync command..."

chmod +x "$SCRIPT_DIR/tunnel-sync.sh"

if [[ -w "$INSTALL_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/tunnel-sync.sh" "$INSTALL_DIR/tunnel-sync"
    echo "   ✓ Installed to: $INSTALL_DIR/tunnel-sync"
else
    echo "   Installing to $INSTALL_DIR requires sudo..."
    sudo ln -sf "$SCRIPT_DIR/tunnel-sync.sh" "$INSTALL_DIR/tunnel-sync"
    echo "   ✓ Installed to: $INSTALL_DIR/tunnel-sync"
fi

# Create launchd plist for auto-start (optional)
echo ""
echo "7. Auto-start configuration..."
read -p "   Start tunnel-sync automatically at login? (y/N): " auto_start

if [[ "$auto_start" == "y" || "$auto_start" == "Y" ]]; then
    mkdir -p "$LAUNCH_AGENTS_DIR"

    cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tunnelsync.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/tunnel-sync</string>
        <string>_daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.tunnel-sync.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.tunnel-sync.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF

    echo "   ✓ Created launchd service"
    echo "   To enable auto-start now, run:"
    echo "     launchctl load $LAUNCH_AGENTS_DIR/$PLIST_NAME"
fi

# Done
echo ""
echo "================================"
echo "  Installation Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Edit your config file if needed:"
echo "   nano $CONFIG_FILE"
echo ""
echo "2. Start tunnel-sync:"
echo "   tunnel-sync start"
echo ""
echo "3. Test by adding a file:"
echo "   touch $LOCAL_DIR/test.txt"
echo "   # Check if it appears on your VM"
echo ""
echo "4. To stop:"
echo "   tunnel-sync stop"
echo ""
echo "For more info: tunnel-sync help"
