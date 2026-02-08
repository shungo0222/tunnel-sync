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
VERSION="2.0.0"

# =============================================================================
# DEFAULT CONFIGURATION
# =============================================================================

REMOTE_HOST=""
REMOTE_USER=""
REMOTE_DIR="~/tunnel-share"
LOCAL_DIR="$HOME/Desktop/tunnel-share"
SYNC_INTERVAL=30
EXCLUDE_PATTERNS=".DS_Store,*.tmp,*.swp,*~,.git"
COPY_TO_CLIPBOARD=true
SHOW_NOTIFICATIONS=true
LOG_FILE="$HOME/.tunnel-sync.log"
LOG_LEVEL="INFO"
MAX_LOG_SIZE_MB=10
AUTO_CLEANUP_DAYS=7
CLEANUP_ON_START=true

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
# LOG ROTATION
# =============================================================================

rotate_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi

    local size_bytes=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    local max_bytes=$((MAX_LOG_SIZE_MB * 1024 * 1024))

    if [[ $size_bytes -gt $max_bytes ]]; then
        local backup="${LOG_FILE}.old"
        mv "$LOG_FILE" "$backup"
        log_info "Log rotated (was ${size_bytes} bytes)"

        # Keep only one backup
        if [[ -f "${LOG_FILE}.old.old" ]]; then
            rm -f "${LOG_FILE}.old.old"
        fi
    fi
}

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
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        # Stale lock: holder process is dead
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            log_debug "Removing stale lock (PID $lock_pid dead)"
            rm -f "$LOCK_FILE"
            return 1
        fi
        return 0
    fi
    return 1
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
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_old_files() {
    local days="${1:-$AUTO_CLEANUP_DAYS}"
    local dry_run="${2:-false}"

    if [[ $days -le 0 ]]; then
        echo "Auto-cleanup disabled (AUTO_CLEANUP_DAYS=0)"
        return 0
    fi

    log_info "Cleaning up files older than $days days"

    local count=0
    local ssh_target=$(get_ssh_target)

    # Find old files in local directory
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        if [[ "$dry_run" == "true" ]]; then
            echo "Would delete: $file"
        else
            rm -f "$file"
            log_info "Deleted old file: $filename"
        fi
        ((count++))
    done < <(find "$LOCAL_DIR" -type f -mtime +${days} -print0 2>/dev/null)

    # Sync deletions to remote
    if [[ $count -gt 0 ]] && [[ "$dry_run" != "true" ]]; then
        sync_to_remote
        echo "Cleaned up $count file(s) older than $days days"
        notify "Cleanup: removed $count old file(s)"
    elif [[ $count -eq 0 ]]; then
        echo "No files older than $days days found"
    else
        echo "Dry run: would delete $count file(s)"
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
    fswatch -0 --latency 2 "$LOCAL_DIR" | while IFS= read -r -d "" event; do
        # Wait for any in-progress sync to finish (instead of skipping)
        local wait_count=0
        while is_locked && [[ $wait_count -lt 30 ]]; do
            sleep 1
            ((wait_count++))
        done

        # Skip if recently synced (cooldown to prevent loops from our own sync)
        local since_sync=$(seconds_since_last_sync)
        if [[ $since_sync -lt 3 ]]; then
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

    # Rotate logs if needed
    rotate_logs

    # Create directories if needed
    mkdir -p "$LOCAL_DIR"
    ssh $(get_ssh_target) "mkdir -p $REMOTE_DIR" 2>/dev/null || true

    # Run cleanup on start if enabled
    if [[ "$CLEANUP_ON_START" == "true" ]] && [[ $AUTO_CLEANUP_DAYS -gt 0 ]]; then
        echo "Running startup cleanup..."
        cleanup_old_files "$AUTO_CLEANUP_DAYS" false 2>/dev/null || true
    fi

    echo "Starting tunnel-sync daemon..."

    # Start in background
    nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"

    echo "Started with PID: $pid"
    echo "Watching: $LOCAL_DIR"
    echo "Remote: $(get_ssh_target):$REMOTE_DIR"
    echo "Log: $LOG_FILE"
    echo "Auto-cleanup: ${AUTO_CLEANUP_DAYS} days"
}

run_daemon() {
    # Disable set -e for daemon mode: fswatch pipe subshells die silently
    # when any command returns non-zero under set -e, killing the watch loop
    set +e
    log_info "Daemon started (v$VERSION)"

    # Clean up stale lock from previous crashed daemon
    rm -f "$LOCK_FILE"

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

    # Start daily cleanup loop in background
    (
        while true; do
            # Sleep for 24 hours
            sleep 86400
            if [[ $AUTO_CLEANUP_DAYS -gt 0 ]]; then
                log_info "Running scheduled cleanup"
                cleanup_old_files "$AUTO_CLEANUP_DAYS" false 2>/dev/null || true
            fi
        done
    ) &
    local cleanup_pid=$!

    # Watch for local changes
    watch_and_sync &
    local watch_pid=$!

    # Wait for any to exit
    wait $watch_pid $pull_pid $cleanup_pid
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
            echo "Auto-cleanup: ${AUTO_CLEANUP_DAYS} days"
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
# HEALTH CHECK
# =============================================================================

health_check() {
    echo "tunnel-sync Health Check"
    echo "========================"
    echo ""

    local all_ok=true

    # Check if daemon is running
    echo -n "Daemon: "
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "✅ Running (PID: $pid)"
        else
            echo "❌ Not running (stale PID)"
            all_ok=false
        fi
    else
        echo "❌ Not running"
        all_ok=false
    fi

    # Check local directory
    echo -n "Local directory: "
    if [[ -d "$LOCAL_DIR" ]]; then
        local local_count=$(ls -1 "$LOCAL_DIR" 2>/dev/null | wc -l | tr -d ' ')
        echo "✅ Exists ($local_count files)"
    else
        echo "❌ Missing: $LOCAL_DIR"
        all_ok=false
    fi

    # Check SSH connectivity
    echo -n "SSH connection: "
    if ssh -o ConnectTimeout=5 $(get_ssh_target) "echo ok" &>/dev/null; then
        echo "✅ Connected to $(get_ssh_target)"
    else
        echo "❌ Cannot connect to $(get_ssh_target)"
        all_ok=false
    fi

    # Check remote directory
    echo -n "Remote directory: "
    if ssh -o ConnectTimeout=5 $(get_ssh_target) "test -d $REMOTE_DIR" &>/dev/null; then
        local remote_count=$(ssh $(get_ssh_target) "ls -1 $REMOTE_DIR 2>/dev/null | wc -l" | tr -d ' ')
        echo "✅ Exists ($remote_count files)"
    else
        echo "❌ Missing: $REMOTE_DIR"
        all_ok=false
    fi

    # Check fswatch
    echo -n "fswatch: "
    if pgrep -f "fswatch.*$LOCAL_DIR" &>/dev/null; then
        echo "✅ Monitoring"
    else
        echo "❌ Not monitoring"
        all_ok=false
    fi

    # Check log file
    echo -n "Log file: "
    if [[ -f "$LOG_FILE" ]]; then
        local log_size=$(ls -lh "$LOG_FILE" | awk '{print $5}')
        echo "✅ $LOG_FILE ($log_size)"
    else
        echo "⚠️ No log file yet"
    fi

    # Check config
    echo -n "Config: "
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "✅ $CONFIG_FILE"
    else
        echo "❌ Missing config file"
        all_ok=false
    fi

    echo ""
    if [[ "$all_ok" == "true" ]]; then
        echo "Overall: ✅ All systems healthy"
        exit 0
    else
        echo "Overall: ❌ Some issues detected"
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
    health      Run health check on all components
    watch       Run in foreground (for debugging)
    push        Manual sync: local → remote
    pull        Manual sync: remote → local
    sync        Manual bidirectional sync
    cleanup     Remove files older than AUTO_CLEANUP_DAYS
    cleanup N   Remove files older than N days
    logs        Show recent log entries
    help        Show this help message

Configuration:
    Edit ~/.tunnel-sync.conf to set your remote host and directories.
    See config.example.sh for available options.

Examples:
    tunnel-sync start           # Start background sync
    tunnel-sync health          # Check all components
    tunnel-sync cleanup         # Remove old files
    tunnel-sync cleanup 3       # Remove files older than 3 days
    tunnel-sync logs            # View recent logs
EOF
}

show_logs() {
    local lines="${1:-50}"
    if [[ -f "$LOG_FILE" ]]; then
        echo "Last $lines lines of $LOG_FILE:"
        echo "---"
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE"
    fi
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
        health)
            load_config
            health_check
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
        cleanup)
            load_config
            local days="${2:-$AUTO_CLEANUP_DAYS}"
            cleanup_old_files "$days" false
            ;;
        logs)
            local lines="${2:-50}"
            show_logs "$lines"
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
