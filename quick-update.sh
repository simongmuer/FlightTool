#!/bin/bash
# Quick update script for development - updates only changed files
# Usage: ./quick-update.sh [container_id] [file_or_directory]

set -e

CONTAINER_ID="${1:-120}"
UPDATE_PATH="${2:-.}"
APP_DIR="/home/flighttool/app"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if we're updating a specific file or directory
if [ -f "$UPDATE_PATH" ]; then
    # Single file update
    log_info "Updating single file: $UPDATE_PATH"
    
    # Get relative path
    REL_PATH="${UPDATE_PATH#./}"
    
    # Copy file to container
    pct push "$CONTAINER_ID" "$UPDATE_PATH" "$APP_DIR/$REL_PATH"
    
    # Set ownership
    pct exec "$CONTAINER_ID" -- chown flighttool:flighttool "$APP_DIR/$REL_PATH"
    
    log_success "File updated: $REL_PATH"
    
elif [ -d "$UPDATE_PATH" ]; then
    # Directory update
    log_info "Updating directory: $UPDATE_PATH"
    
    # Create temporary archive
    TEMP_FILE="/tmp/quick_update_$(date +%s).tar.gz"
    tar czf "$TEMP_FILE" -C "$(dirname "$UPDATE_PATH")" "$(basename "$UPDATE_PATH")"
    
    # Copy to container and extract
    pct push "$CONTAINER_ID" "$TEMP_FILE" /tmp/update.tar.gz
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && tar xzf /tmp/update.tar.gz && rm /tmp/update.tar.gz"
    
    # Set ownership
    DIR_NAME="$(basename "$UPDATE_PATH")"
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR/$DIR_NAME"
    
    # Clean up
    rm "$TEMP_FILE"
    
    log_success "Directory updated: $UPDATE_PATH"
else
    log_warn "Path not found: $UPDATE_PATH"
    exit 1
fi

# Restart application if it's a server file
if [[ "$UPDATE_PATH" =~ server/ ]] || [[ "$UPDATE_PATH" =~ package\.json ]] || [[ "$UPDATE_PATH" =~ \.env ]]; then
    log_info "Server files changed, restarting application..."
    
    # Restart systemd service if it exists
    if pct exec "$CONTAINER_ID" -- systemctl is-active flighttool >/dev/null 2>&1; then
        pct exec "$CONTAINER_ID" -- systemctl restart flighttool
        log_success "Application restarted via systemd"
    else
        # Manual restart
        pct exec "$CONTAINER_ID" -- pkill -f 'node.*flighttool' || true
        sleep 2
        pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && nohup npm start > /var/log/flighttool.log 2>&1 &"
        log_success "Application restarted manually"
    fi
    
    # Verify
    sleep 3
    if pct exec "$CONTAINER_ID" -- curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Application is running correctly"
    else
        log_warn "Application may not be running correctly - check logs"
    fi
fi

log_success "Quick update completed!"