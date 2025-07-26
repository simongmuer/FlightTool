#!/bin/bash
# Script to update FlightTool codebase within existing container
# Usage: ./update-container.sh [container_id] [repository_url]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Default values
CONTAINER_ID="${1:-120}"
APP_REPO="${2:-https://github.com/your-username/flighttool.git}"
APP_DIR="/home/flighttool/app"
BACKUP_DIR="/home/flighttool/backup"

# Check if container exists
check_container() {
    log_info "Checking if container $CONTAINER_ID exists..."
    if ! pct status "$CONTAINER_ID" >/dev/null 2>&1; then
        log_error "Container $CONTAINER_ID does not exist"
        exit 1
    fi
    
    if [ "$(pct status "$CONTAINER_ID")" != "status: running" ]; then
        log_warn "Container $CONTAINER_ID is not running. Starting..."
        pct start "$CONTAINER_ID"
        sleep 5
    fi
    
    log_success "Container $CONTAINER_ID is running"
}

# Create backup of current application
create_backup() {
    log_info "Creating backup of current application..."
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DIR/flighttool_backup_$TIMESTAMP"
    
    pct exec "$CONTAINER_ID" -- mkdir -p "$BACKUP_DIR"
    
    if pct exec "$CONTAINER_ID" -- test -d "$APP_DIR"; then
        pct exec "$CONTAINER_ID" -- cp -r "$APP_DIR" "$BACKUP_PATH"
        log_success "Backup created at $BACKUP_PATH"
        echo "$BACKUP_PATH" > /tmp/backup_path_$CONTAINER_ID
    else
        log_warn "No existing application directory found"
    fi
}

# Stop application service
stop_application() {
    log_info "Stopping FlightTool service..."
    
    # Stop systemd service if it exists
    pct exec "$CONTAINER_ID" -- systemctl stop flighttool || log_warn "Systemd service not found or already stopped"
    
    # Kill any node processes
    pct exec "$CONTAINER_ID" -- pkill -f 'node.*flighttool' || log_warn "No Node.js processes found"
    
    log_success "Application stopped"
}

# Update codebase
update_codebase() {
    log_info "Updating codebase from repository..."
    
    if [ -n "$APP_REPO" ]; then
        # Remove old application directory
        pct exec "$CONTAINER_ID" -- rm -rf "$APP_DIR"
        
        # Clone fresh copy
        pct exec "$CONTAINER_ID" -- git clone "$APP_REPO" "$APP_DIR"
        
        # Set ownership
        pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"
        
        log_success "Codebase updated from repository"
    else
        log_error "No repository URL provided"
        exit 1
    fi
}

# Update from local directory (alternative method)
update_from_local() {
    local LOCAL_DIR="$1"
    
    if [ -z "$LOCAL_DIR" ] || [ ! -d "$LOCAL_DIR" ]; then
        log_error "Local directory not specified or doesn't exist"
        return 1
    fi
    
    log_info "Updating codebase from local directory: $LOCAL_DIR"
    
    # Remove old application directory
    pct exec "$CONTAINER_ID" -- rm -rf "$APP_DIR"
    pct exec "$CONTAINER_ID" -- mkdir -p "$APP_DIR"
    
    # Copy files to container
    cd "$LOCAL_DIR"
    tar czf - . | pct push "$CONTAINER_ID" - "$APP_DIR/update.tar.gz"
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && tar xzf update.tar.gz && rm update.tar.gz"
    
    # Set ownership
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"
    
    log_success "Codebase updated from local directory"
}

# Install dependencies and build
install_and_build() {
    log_info "Installing dependencies and building application..."
    
    # Install dependencies
    pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && npm install"
    
    # Create environment file if it doesn't exist
    if ! pct exec "$CONTAINER_ID" -- test -f "$APP_DIR/.env"; then
        log_info "Creating environment configuration..."
        pct exec "$CONTAINER_ID" -- bash -c "cat > '$APP_DIR/.env' << 'EOF'
NODE_ENV=production
DATABASE_URL=postgresql://flighttool:\$(cat /etc/flighttool-db-password 2>/dev/null || echo 'default_password')@localhost:5432/flighttool
SESSION_SECRET=\$(openssl rand -base64 32)
PORT=3000
EOF"
    fi
    
    # Build application
    if pct exec "$CONTAINER_ID" -- test -f "$APP_DIR/build-production.sh"; then
        pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && chmod +x build-production.sh && ./build-production.sh"
    else
        # Fallback build process
        pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && npm run build"
    fi
    
    # Set permissions
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"
    
    log_success "Dependencies installed and application built"
}

# Start application service
start_application() {
    log_info "Starting FlightTool service..."
    
    # Start systemd service if it exists
    if pct exec "$CONTAINER_ID" -- systemctl is-enabled flighttool >/dev/null 2>&1; then
        pct exec "$CONTAINER_ID" -- systemctl start flighttool
        pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l
    else
        log_warn "Systemd service not found. Starting manually..."
        pct exec "$CONTAINER_ID" -- bash -c "cd '$APP_DIR' && nohup npm start > /var/log/flighttool.log 2>&1 &"
    fi
    
    log_success "Application started"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    sleep 5
    
    # Check if service is running
    if pct exec "$CONTAINER_ID" -- curl -f http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Health check passed - application is running"
    else
        log_error "Health check failed - application may not be running correctly"
        
        # Show recent logs
        log_info "Recent application logs:"
        pct exec "$CONTAINER_ID" -- tail -20 /var/log/flighttool.log || echo "No logs found"
        
        return 1
    fi
}

# Rollback function
rollback() {
    local BACKUP_PATH_FILE="/tmp/backup_path_$CONTAINER_ID"
    
    if [ -f "$BACKUP_PATH_FILE" ]; then
        local BACKUP_PATH=$(cat "$BACKUP_PATH_FILE")
        
        log_warn "Rolling back to previous version..."
        
        # Stop current application
        stop_application
        
        # Restore backup
        pct exec "$CONTAINER_ID" -- rm -rf "$APP_DIR"
        pct exec "$CONTAINER_ID" -- cp -r "$BACKUP_PATH" "$APP_DIR"
        pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool "$APP_DIR"
        
        # Start application
        start_application
        
        log_success "Rollback completed"
        rm "$BACKUP_PATH_FILE"
    else
        log_error "No backup found for rollback"
    fi
}

# Print usage
print_usage() {
    echo "Usage: $0 [container_id] [repository_url|--local <directory>] [--rollback]"
    echo ""
    echo "Options:"
    echo "  container_id      Container ID (default: 120)"
    echo "  repository_url    Git repository URL to update from"
    echo "  --local <dir>     Update from local directory instead of git"
    echo "  --rollback        Rollback to previous version"
    echo ""
    echo "Examples:"
    echo "  $0 120 https://github.com/user/flighttool.git"
    echo "  $0 120 --local /path/to/flighttool"
    echo "  $0 120 --rollback"
}

# Main execution
main() {
    log_info "FlightTool Container Update Script"
    log_info "================================="
    
    # Parse arguments
    if [ "$2" = "--rollback" ] || [ "$1" = "--rollback" ]; then
        check_container
        rollback
        exit 0
    fi
    
    if [ "$2" = "--local" ]; then
        LOCAL_DIR="$3"
        if [ -z "$LOCAL_DIR" ]; then
            log_error "Local directory path required with --local option"
            print_usage
            exit 1
        fi
    fi
    
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        print_usage
        exit 0
    fi
    
    # Main update process
    check_container
    create_backup
    stop_application
    
    if [ -n "$LOCAL_DIR" ]; then
        update_from_local "$LOCAL_DIR"
    else
        update_codebase
    fi
    
    install_and_build
    start_application
    
    if verify_deployment; then
        log_success "Update completed successfully!"
        log_info "Application is running at: http://$(pct config $CONTAINER_ID | grep -E '^net[0-9]:' | head -1 | cut -d'=' -f2 | cut -d',' -f1 | cut -d'/' -f1):3000"
        
        # Clean up backup reference
        rm -f "/tmp/backup_path_$CONTAINER_ID"
    else
        log_error "Update failed. Use '$0 $CONTAINER_ID --rollback' to revert changes"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"