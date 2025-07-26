#!/bin/bash
# Simplified script to update FlightTool from public GitHub repository
# Usage: ./update-from-github.sh [container_id] [github_repo_url]

set -e

CONTAINER_ID="${1:-120}"
GITHUB_REPO="$2"
APP_DIR="/home/flighttool/app"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate repository URL
if [ -z "$GITHUB_REPO" ]; then
    log_error "GitHub repository URL is required"
    echo "Usage: $0 [container_id] <github_repo_url>"
    echo "Example: $0 120 https://github.com/username/flighttool.git"
    exit 1
fi

# Ensure it's a public HTTPS URL
if [[ ! "$GITHUB_REPO" =~ ^https://github\.com/ ]]; then
    log_error "Please provide a public GitHub HTTPS URL (https://github.com/...)"
    exit 1
fi

log_info "FlightTool Public Repository Update"
log_info "Container: $CONTAINER_ID"
log_info "Repository: $GITHUB_REPO"

# Check container status
if ! pct status "$CONTAINER_ID" >/dev/null 2>&1; then
    log_error "Container $CONTAINER_ID does not exist"
    exit 1
fi

if [ "$(pct status "$CONTAINER_ID")" != "status: running" ]; then
    log_warn "Starting container $CONTAINER_ID..."
    pct start "$CONTAINER_ID"
    sleep 3
fi

# Create backup
BACKUP_DIR="/home/flighttool/backup/$(date +%Y%m%d_%H%M%S)"
log_info "Creating backup..."
if pct exec "$CONTAINER_ID" -- test -d "$APP_DIR"; then
    pct exec "$CONTAINER_ID" -- mkdir -p "$(dirname "$BACKUP_DIR")"
    pct exec "$CONTAINER_ID" -- cp -r "$APP_DIR" "$BACKUP_DIR"
    log_success "Backup created: $BACKUP_DIR"
fi

# Stop application
log_info "Stopping application..."
pct exec "$CONTAINER_ID" -- systemctl stop flighttool 2>/dev/null || true
pct exec "$CONTAINER_ID" -- pkill -f 'node.*flighttool' 2>/dev/null || true

# Update from repository
log_info "Downloading latest code from repository..."
pct exec "$CONTAINER_ID" -- rm -rf "$APP_DIR"
pct exec "$CONTAINER_ID" -- git clone --depth 1 "$GITHUB_REPO" "$APP_DIR"

# Set permissions
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"

# Install dependencies and build
log_info "Installing dependencies..."
pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && npm install --production=false"

log_info "Building application..."
if pct exec "$CONTAINER_ID" -- test -f "$APP_DIR/build-production.sh"; then
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && chmod +x build-production.sh && ./build-production.sh"
else
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && npm run build"
fi

# Ensure environment file exists
if ! pct exec "$CONTAINER_ID" -- test -f "$APP_DIR/.env"; then
    log_info "Creating production environment file..."
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && cp .env.example .env 2>/dev/null || echo 'NODE_ENV=production' > .env"
fi

# Start application
log_info "Starting application..."
pct exec "$CONTAINER_ID" -- systemctl start flighttool 2>/dev/null || \
pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && nohup npm start > /var/log/flighttool.log 2>&1 &"

# Verify
sleep 5
if pct exec "$CONTAINER_ID" -- curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
    log_success "Update completed successfully!"
    log_success "Application is running and healthy"
    
    # Get container IP for access
    CONTAINER_IP=$(pct config "$CONTAINER_ID" | grep -E '^net[0-9]:' | head -1 | cut -d'=' -f2 | cut -d',' -f1 | cut -d'/' -f1)
    if [ -n "$CONTAINER_IP" ]; then
        log_info "Access your application at: http://$CONTAINER_IP:3000"
    fi
else
    log_error "Update completed but application health check failed"
    log_warn "Check application logs for issues"
    log_info "Rollback if needed: cp -r '$BACKUP_DIR' '$APP_DIR' && systemctl restart flighttool"
    exit 1
fi