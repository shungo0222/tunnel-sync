# tunnel-sync configuration
# Copy this file to ~/.tunnel-sync.conf and edit with your settings

# =============================================================================
# REMOTE VM SETTINGS
# =============================================================================

# SSH host for your VM
# Can be a hostname, IP address, or SSH config alias
# Examples:
#   REMOTE_HOST="kumo"                    # SSH config alias
#   REMOTE_HOST="192.168.1.100"           # IP address
#   REMOTE_HOST="user@192.168.1.100"      # User + IP
REMOTE_HOST="your-vm-hostname"

# SSH user (leave empty if already included in REMOTE_HOST or SSH config)
REMOTE_USER=""

# Remote directory for synced files
# Use ~ for home directory
REMOTE_DIR="~/tunnel-share"

# =============================================================================
# LOCAL SETTINGS
# =============================================================================

# Local directory for synced files
LOCAL_DIR="$HOME/Desktop/tunnel-share"

# =============================================================================
# SYNC SETTINGS
# =============================================================================

# Interval (seconds) between remote → local sync checks
# Lower = more responsive, higher = less resource usage
SYNC_INTERVAL=30

# File patterns to exclude from sync (comma-separated)
# Common patterns: .DS_Store (macOS), *.tmp, *.swp (vim), *~ (backup files)
EXCLUDE_PATTERNS=".DS_Store,*.tmp,*.swp,*~,.git"

# =============================================================================
# CLIPBOARD SETTINGS
# =============================================================================

# Automatically copy remote path to clipboard when a file is added locally
# Set to "false" to disable
COPY_TO_CLIPBOARD=true

# =============================================================================
# NOTIFICATION SETTINGS
# =============================================================================

# Show macOS notifications on sync events
# Set to "false" to disable
SHOW_NOTIFICATIONS=true

# =============================================================================
# LOGGING
# =============================================================================

# Log file location
LOG_FILE="$HOME/.tunnel-sync.log"

# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="INFO"

# Maximum log file size in MB (logs are rotated when exceeded)
MAX_LOG_SIZE_MB=10

# =============================================================================
# AUTO-CLEANUP SETTINGS
# =============================================================================

# Automatically delete files older than N days (0 to disable)
# This helps prevent the sync folder from accumulating old screenshots
AUTO_CLEANUP_DAYS=7

# Run cleanup when daemon starts
CLEANUP_ON_START=true
