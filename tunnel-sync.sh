#!/bin/bash

# tunnel-sync - Bidirectional file sync between local machine and remote VM
# https://github.com/shungo0222/tunnel-sync

set -e

# =============================================================================
# CONSTANTS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.tunnel-sync.conf"
PID_FILE="$HOME/.tunnel-sync.pid"
LOCK_FILE="$HOME/.tunnel-sync.lock"
LAST_SYNC_FILE="$HOME/.tunnel-sync.lastsync"
VERSION="1.2.0"

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================

REMOTE_HOST=""
REMOTE_USER=""
REMOTE_DIR="~/tunnel-share"
LOCAL_DIR="$HOME/tunnel-share"
SYNC_INTERVAL=30
EXCLUDE_PATTERNS=".DS_Store,*.tmp,*.swp,*~,.git"
COPY_TO_CLIPBOARD=true
SHOW_NOTIFICATIONS=true
LOG_FILE="$HOME/.tunnel-sync.log"
LOG_LEVEL="INFO"
MAX_LOG_SIZE=10

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log level filtering
    case "$LOG_LEVEL" in
        DEBUG) allowed_levels="DEBUG INFO WARN ERROR" ;;
        INFO)  allowed_levels="INFO WARN ERROR" ;;
        WARN)  allowed_levels="WARN ERROR" ;;
        ERROR) allowed_levels="ERROR" ;;
        *)     allowed_levels="INFO WARN ERROR" ;;
    esac

    if [[ " $allowed_levels " =~ " $level " ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

        # Also print to stdout if running in foreground
        if [[ "$FOREGROUND" == "true" ]]; then
            echo "[$level] $message"
        fi
    fi
}

log_debug() { log "DEBUG" "$1"; }
log_info()  { log "INFO" "$1"; }
log_warn()  { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# =============================================================================
# CONFIGURATION
# =============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_debug "Loaded config from $CONFIG_FILE"
    else
        log_error "Config file not found: $CONFIG_FILE"
        echo "Error: Config file not found: $CONFIG_FILE"
        echo "Please copy config.example.sh to ~/.tunnel-sync.conf and edit it."
        exit 1
    fi

    # Validate required settings
    if [[ -z "$REMOTE_HOST" || "$REMOTE_HOST" == "your-vm-hostname" ]]; then
        log_error "REMOTE_HOST not configured"
        echo "Error: REMOTE_HOST not configured in $CONFIG_FILE"
        exit 1
    fi
}

# =============================================================================
# UTILITIES
# =============================================================================

check_dependencies() {
    local missing=()

    if ! command -v fswatch &> /dev/null; then
        missing+=("fswatch")
    fi

    if ! command -v rsync &> /dev/null; then
        missing+=("rsync")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing dependencies: ${missing[*]}"
        echo "Install with: brew install ${missing[*]}"
        exit 1
    fi
}

notify() {
    local message="$1"
    if [[ "$SHOW_NOTIFICATIONS" == "true" ]] && command -v osascript &> /dev/null; then
        osascript -e "display notification \"$message\" with title \"tunnel-sync\""
    fi
}

copy_to_clipboard() {
    local text="$1"
    if [[ "$COPY_TO_CLIPBOARD" == "true" ]] && command -v pbcopy &> /dev/null; then
        echo -n "$text" | pbcopy
        log_info "Copied to clipboard: $text"
    fi
}

get_remote_path() {
    local filename="$1"
    echo "${REMOTE_DIR}/${filename}"
}

build_exclude_args() {
    local exclude_args=""
    IFS=',' read -ra patterns <<< "$EXCLUDE_PATTERNS"
    for pattern in "${patterns[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        exclude_args="$exclude_args --exclude='$pattern'"
    done
    echo "$exclude_args"
}

get_ssh_target() {
    if [[ -n "$REMOTE_USER" ]]; then
        echo "${REMOTE_USER}@${REMOTE_HOST}"
    else
        echo "$REMOTE_HOST"
    fi
}

# =============================================================================
# LOCK FUNCTIONS (Prevent infinite sync loops)
# =============================================================================

acquire_lock() {
    echo $$ > "$LOCK_FILE"
    log_debug "Lock acquired"
}

release_lock() {
    rm -f "$LOCK_FILE"
    log_debug "Lock released"
}

is_locked() {
    [[ -f "$LOCK_FILE" ]]
}

record_sync_time() {
    date +%s > "$LAST_SYNC_FILE"
}

seconds_since_last_sync() {
    if [[ -f "$LAST_SYNC_FILE" ]]; then
        local last_sync=$(cat "$LAST_SYNC_FILE")
        local now=$(date +%s)
        echo $((now - last_sync))
    else
        echo 999
    fi
}

# =============================================================================
# SYNC FUNCTIONS
# =============================================================================

sync_to_remote() {
    local exclude_args=$(build_exclude_args)
    local ssh_target=$(get_ssh_target)

    acquire_lock
    log_debug "Syncing local → remote"

    eval rsync -avz --delete $exclude_args \
        "${LOCAL_DIR}/" \
        "${ssh_target}:${REMOTE_DIR}/" \
        2>&1 | while read line; do log_debug "rsync: $line"; done

    local result=${PIPESTATUS[0]}

    # Record sync completion time
    record_sync_time

    # Keep lock for a moment to let fswatch events settle
    sleep 2
    release_lock

    return $result
}

sync_from_remote() {
    local exclude_args=$(build_exclude_args)
    local ssh_target=$(get_ssh_target)

    acquire_lock
    log_debug "Syncing remote → local"

    # Note: No --delete here to prevent accidental deletion of local files
    # Deletions should be explicit user actions
    eval rsync -avz $exclude_args \
        "${ssh_target}:${REMOTE_DIR}/" \
        "${LOCAL_DIR}/" \
        2>&1 | while read line; do log_debug "rsync: $line"; done

    local result=${PIPESTATUS[0]}

    # Record sync completion time
    record_sync_time

    # Keep lock for a moment to let fswatch events settle
    sleep 3
    release_lock

    return $result
}

sync_bidirectional() {
    sync_to_remote
    sync_from_remote
}

# =============================================================================
# WATCH FUNCTION
# =============================================================================

watch_and_sync() {
    log_info "Starting watch on $LOCAL_DIR"
    echo "Watching $LOCAL_DIR for changes..."
    echo "Press Ctrl+C to stop"

    # Track last processed file to avoid immediate duplicates
    local last_processed=""
    local last_processed_time=0

    # Watch for file changes (latency helps batch rapid events)
    fswatch -0 --latency 2 "$LOCAL_DIR" | while read -d "" event; do
        # Skip if sync is in progress (prevents infinite loop)
        if is_locked; then
            log_debug "Skipping event (sync in progress): $event"
            continue
        fi

        # Skip if recently synced (cooldown period to prevent loops)
        local since_sync=$(seconds_since_last_sync)
        if [[ $since_sync -lt 5 ]]; then
            log_debug "Skipping event (cooldown ${since_sync}s): $event"
            continue
        fi

        # Get relative filename
        local filename=$(basename "$event")
        local relative_path="${event#$LOCAL_DIR/}"

        # Skip the directory itself
        if [[ "$event" == "$LOCAL_DIR" ]]; then
            continue
        fi

        # Skip excluded patterns
        local skip=false
        IFS=',' read -ra patterns <<< "$EXCLUDE_PATTERNS"
        for pattern in "${patterns[@]}"; do
            pattern=$(echo "$pattern" | xargs)
            if [[ "$filename" == $pattern ]]; then
                skip=true
                break
            fi
        done

        if [[ "$skip" == "true" ]]; then
            continue
        fi

        # Check if file exists (might be a delete event)
        if [[ -f "$event" ]]; then
            log_info "File changed: $relative_path"

            # Debounce: skip if same file within 3 seconds
            local current_time=$(date +%s)
            if [[ "$event" == "$last_processed" ]] && [[ $((current_time - last_processed_time)) -lt 3 ]]; then
                log_debug "Debounced: $relative_path"
                continue
            fi

            # Sync to remote
            if sync_to_remote; then
                local remote_path=$(get_remote_path "$relative_path")
                copy_to_clipboard "$remote_path"
                notify "Synced: $filename"
                echo "✓ Synced: $filename → Clipboard: $remote_path"
                last_processed="$event"
                last_processed_time=$current_time
            else
                log_error "Failed to sync: $relative_path"
                notify "Sync failed: $filename"
            fi
        else
            # File was deleted
            log_info "File deleted: $relative_path"
            if sync_to_remote; then
                log_info "Deletion synced"
            fi
        fi
    done
}

# =============================================================================
# DAEMON FUNCTIONS
# =============================================================================

start_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid=$(cat "$PID_FILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            echo "tunnel-sync is already running (PID: $existing_pid)"
            exit 1
        else
            rm "$PID_FILE"
        fi
    fi

    # Clean up any stale files
    rm -f "$LOCK_FILE"
    rm -f "$LAST_SYNC_FILE"

    # Create directories if needed
    mkdir -p "$LOCAL_DIR"
    ssh $(get_ssh_target) "mkdir -p $REMOTE_DIR" 2>/dev/null || true

    echo "Starting tunnel-sync daemon..."

    # Start in background
    nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"

    echo "Started with PID: $pid"
    echo "Watching: $LOCAL_DIR"
    echo "Remote: $(get_ssh_target):$REMOTE_DIR"
    echo "Log: $LOG_FILE"
}

run_daemon() {
    log_info "Daemon started"

    # Clean up lock file on exit
    trap "release_lock; exit" INT TERM EXIT

    # Start bidirectional sync loop in background
    (
        while true; do
            sleep "$SYNC_INTERVAL"
            if ! is_locked; then
                sync_from_remote 2>/dev/null || true
            fi
        done
    ) &
    local pull_pid=$!

    # Watch for local changes
    watch_and_sync &
    local watch_pid=$!

    # Wait for either to exit
    wait $watch_pid $pull_pid
}

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping tunnel-sync (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            # Kill child processes
            pkill -P "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            rm -f "$LOCK_FILE"
            rm -f "$LAST_SYNC_FILE"
            echo "Stopped"
        else
            echo "tunnel-sync is not running (stale PID file)"
            rm -f "$PID_FILE"
            rm -f "$LOCK_FILE"
            rm -f "$LAST_SYNC_FILE"
        fi
    else
        echo "tunnel-sync is not running"
    fi
}

status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "tunnel-sync is running (PID: $pid)"
            echo "Local:  $LOCAL_DIR"
            echo "Remote: $(get_ssh_target):$REMOTE_DIR"
            echo "Sync interval: ${SYNC_INTERVAL}s"
            if is_locked; then
                echo "Status: Syncing..."
            else
                echo "Status: Watching"
            fi
            exit 0
        else
            echo "tunnel-sync is not running (stale PID file)"
            rm "$PID_FILE"
            exit 1
        fi
    else
        echo "tunnel-sync is not running"
        exit 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

usage() {
    cat << EOF
tunnel-sync v$VERSION - Bidirectional file sync with clipboard integration

Usage: tunnel-sync <command>

Commands:
    start       Start the sync daemon in background
    stop        Stop the sync daemon
    status      Show daemon status
    watch       Run in foreground (for debugging)
    push        Manual sync: local → remote
    pull        Manual sync: remote → local
    sync        Manual bidirectional sync
    help        Show this help message

Configuration:
    Edit ~/.tunnel-sync.conf to set your remote host and directories.
    See config.example.sh for available options.

Examples:
    tunnel-sync start           # Start background sync
    tunnel-sync watch           # Run in foreground
    tunnel-sync push            # One-time upload to VM
    tunnel-sync pull            # One-time download from VM
EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
        start)
            load_config
            check_dependencies
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        status)
            load_config
            status
            ;;
        watch)
            load_config
            check_dependencies
            FOREGROUND=true
            mkdir -p "$LOCAL_DIR"
            watch_and_sync
            ;;
        push)
            load_config
            check_dependencies
            echo "Syncing local → remote..."
            if sync_to_remote; then
                echo "Done"
            else
                echo "Failed"
                exit 1
            fi
            ;;
        pull)
            load_config
            check_dependencies
            echo "Syncing remote → local..."
            if sync_from_remote; then
                echo "Done"
            else
                echo "Failed"
                exit 1
            fi
            ;;
        sync)
            load_config
            check_dependencies
            echo "Bidirectional sync..."
            if sync_bidirectional; then
                echo "Done"
            else
                echo "Failed"
                exit 1
            fi
            ;;
        _daemon)
            # Internal command for running as daemon
            load_config
            check_dependencies
            run_daemon
            ;;
        help|--help|-h)
            usage
            ;;
        version|--version|-v)
            echo "tunnel-sync v$VERSION"
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'tunnel-sync help' for usage information."
            exit 1
            ;;
    esac
}

main "$@"
