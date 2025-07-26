#!/bin/bash
# Script to sync local development changes to container in real-time
# Usage: ./sync-local-to-container.sh [container_id] [watch_directory]

set -e

CONTAINER_ID="${1:-120}"
WATCH_DIR="${2:-.}"
APP_DIR="/home/flighttool/app"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if inotify-tools is installed
if ! command -v inotifywait &> /dev/null; then
    log_error "inotifywait is required but not installed"
    log_info "Install it with: sudo apt-get install inotify-tools"
    exit 1
fi

# Check if container exists
if ! pct status "$CONTAINER_ID" >/dev/null 2>&1; then
    log_error "Container $CONTAINER_ID does not exist"
    exit 1
fi

if [ "$(pct status "$CONTAINER_ID")" != "status: running" ]; then
    log_error "Container $CONTAINER_ID is not running"
    exit 1
fi

# Initial sync
log_info "Performing initial sync of $WATCH_DIR to container $CONTAINER_ID..."

# Create archive excluding node_modules, .git, and other unnecessary files
tar czf /tmp/initial_sync.tar.gz \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='*.log' \
    --exclude='.env.local' \
    -C "$(dirname "$WATCH_DIR")" "$(basename "$WATCH_DIR")"

# Copy to container and extract
pct push "$CONTAINER_ID" /tmp/initial_sync.tar.gz /tmp/sync.tar.gz
pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && tar xzf /tmp/sync.tar.gz && rm /tmp/sync.tar.gz"
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"

# Clean up
rm /tmp/initial_sync.tar.gz

log_success "Initial sync completed"

# Function to sync a changed file
sync_file() {
    local file_path="$1"
    local rel_path="${file_path#$WATCH_DIR/}"
    
    # Skip certain files/directories
    if [[ "$rel_path" =~ ^(node_modules|\.git|dist|\.env\.local) ]]; then
        return
    fi
    
    if [ -f "$file_path" ]; then
        log_info "Syncing: $rel_path"
        pct push "$CONTAINER_ID" "$file_path" "$APP_DIR/$rel_path"
        pct exec "$CONTAINER_ID" -- chown flighttool:flighttool "$APP_DIR/$rel_path"
        
        # Restart if server file changed
        if [[ "$rel_path" =~ ^server/ ]] || [[ "$rel_path" =~ package\.json$ ]]; then
            log_warn "Server file changed - restarting application..."
            restart_application
        fi
    elif [ -d "$file_path" ]; then
        log_info "Creating directory: $rel_path"
        pct exec "$CONTAINER_ID" -- mkdir -p "$APP_DIR/$rel_path"
        pct exec "$CONTAINER_ID" -- chown flighttool:flighttool "$APP_DIR/$rel_path"
    fi
}

# Function to restart application
restart_application() {
    if pct exec "$CONTAINER_ID" -- systemctl is-active flighttool >/dev/null 2>&1; then
        pct exec "$CONTAINER_ID" -- systemctl restart flighttool
    else
        pct exec "$CONTAINER_ID" -- pkill -f 'node.*flighttool' || true
        sleep 1
        pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && nohup npm start > /var/log/flighttool.log 2>&1 &"
    fi
    
    # Brief verification
    sleep 2
    if pct exec "$CONTAINER_ID" -- curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Application restarted successfully"
    else
        log_warn "Application restart may have failed"
    fi
}

# Function to handle file deletion
handle_delete() {
    local file_path="$1"
    local rel_path="${file_path#$WATCH_DIR/}"
    
    if [[ "$rel_path" =~ ^(node_modules|\.git|dist) ]]; then
        return
    fi
    
    log_warn "Deleting: $rel_path"
    pct exec "$CONTAINER_ID" -- rm -f "$APP_DIR/$rel_path" || true
}

# Start watching for changes
log_info "Starting file watcher on $WATCH_DIR..."
log_info "Press Ctrl+C to stop syncing"

# Trap to handle cleanup
trap 'log_info "Stopping file sync..."; exit 0' INT TERM

# Watch for file changes
inotifywait -m -r -e modify,create,delete,move \
    --exclude '(node_modules|\.git|dist|\..*\.swp|\..*\.tmp)' \
    --format '%w%f %e' \
    "$WATCH_DIR" | while read file event; do
    
    case $event in
        CREATE|MODIFY|MOVED_TO)
            sync_file "$file"
            ;;
        DELETE|MOVED_FROM)
            handle_delete "$file"
            ;;
    esac
done