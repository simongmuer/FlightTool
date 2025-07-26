#!/bin/bash
# Fix FlightTool permissions and service issues
# Run this script if you get permission denied errors

set -e

CONTAINER_ID="100"  # Change this to your container ID if different

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if container exists
if ! pct list | grep -q "^${CONTAINER_ID}"; then
    log_error "Container $CONTAINER_ID not found"
    exit 1
fi

log_info "Fixing permissions for FlightTool in container $CONTAINER_ID..."

# Stop the service
log_info "Stopping FlightTool service..."
pct exec "$CONTAINER_ID" -- systemctl stop flighttool || true

# Fix user and group
log_info "Ensuring flighttool user exists..."
pct exec "$CONTAINER_ID" -- id flighttool || pct exec "$CONTAINER_ID" -- useradd -r -s /bin/bash flighttool

# Create app directory if it doesn't exist
log_info "Creating application directory..."
pct exec "$CONTAINER_ID" -- mkdir -p /home/flighttool/app

# Fix ownership and permissions
log_info "Fixing ownership and permissions..."
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool
pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool
pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool/app

# Fix specific file permissions
if pct exec "$CONTAINER_ID" -- test -f /home/flighttool/app/.env; then
    log_info "Fixing .env file permissions..."
    pct exec "$CONTAINER_ID" -- chmod 644 /home/flighttool/app/.env
    pct exec "$CONTAINER_ID" -- chown flighttool:flighttool /home/flighttool/app/.env
fi

# Fix npm global directory permissions
log_info "Fixing npm permissions..."
pct exec "$CONTAINER_ID" -- mkdir -p /home/flighttool/.npm
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/.npm

# Update systemd service to use bash shell
log_info "Updating systemd service..."
pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/systemd/system/flighttool.service << 'EOF'
[Unit]
Description=FlightTool Personal Flight Tracking Application
After=network.target postgresql.service

[Service]
Type=simple
User=flighttool
Group=flighttool
WorkingDirectory=/home/flighttool/app
Environment=NODE_ENV=production
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=/home/flighttool
EnvironmentFile=/home/flighttool/app/.env
ExecStart=/usr/bin/npm start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10

# Security settings (relaxed for debugging)
NoNewPrivileges=false
PrivateTmp=false
ProtectSystem=false
ProtectHome=false
ReadWritePaths=/home/flighttool

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF"

# Reload systemd
log_info "Reloading systemd..."
pct exec "$CONTAINER_ID" -- systemctl daemon-reload

# Test if application files exist
if pct exec "$CONTAINER_ID" -- test -f /home/flighttool/app/package.json; then
    log_info "Application files found"
    
    # Test npm as flighttool user
    log_info "Testing npm access..."
    if pct exec "$CONTAINER_ID" -- sudo -u flighttool bash -c "cd /home/flighttool/app && npm --version"; then
        log_info "✓ npm access working"
    else
        log_warn "⚠ npm access issues detected"
    fi
    
    # Install dependencies if needed
    if ! pct exec "$CONTAINER_ID" -- test -d /home/flighttool/app/node_modules; then
        log_info "Installing dependencies..."
        pct exec "$CONTAINER_ID" -- sudo -u flighttool bash -c "cd /home/flighttool/app && npm install"
        pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/app/node_modules
    fi
    
    # Try to start the service
    log_info "Starting FlightTool service..."
    pct exec "$CONTAINER_ID" -- systemctl enable flighttool
    pct exec "$CONTAINER_ID" -- systemctl start flighttool
    
    # Wait a moment and check status
    sleep 5
    
    if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet flighttool; then
        log_info "✓ FlightTool service is running successfully"
        pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l
    else
        log_error "✗ FlightTool service failed to start"
        echo "Service logs:"
        pct exec "$CONTAINER_ID" -- journalctl -u flighttool -n 20 --no-pager
        echo
        echo "Manual troubleshooting commands:"
        echo "pct enter $CONTAINER_ID"
        echo "sudo -u flighttool bash"
        echo "cd /home/flighttool/app"
        echo "npm start"
    fi
else
    log_warn "No application files found in /home/flighttool/app"
    log_info "You may need to deploy the application first"
fi

log_info "Permission fix completed"