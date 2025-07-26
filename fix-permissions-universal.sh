#!/bin/bash
# Universal FlightTool permissions fix
# Works in Docker, LXC, or direct system deployment

set -e

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

# Detect app directory
APP_DIR=""
if [ -d "/home/flighttool/app" ]; then
    APP_DIR="/home/flighttool/app"
elif [ -d "/opt/flighttool" ]; then
    APP_DIR="/opt/flighttool"
elif [ -d "$(pwd)" ] && [ -f "$(pwd)/package.json" ]; then
    APP_DIR="$(pwd)"
else
    log_error "Cannot find FlightTool application directory"
    exit 1
fi

log_info "Found FlightTool in: $APP_DIR"

# Check if we're root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Stop service if it exists
log_info "Stopping FlightTool service if running..."
systemctl stop flighttool 2>/dev/null || true

# Create flighttool user if it doesn't exist
if ! id flighttool &>/dev/null; then
    log_info "Creating flighttool user..."
    useradd -r -s /bin/bash flighttool
fi

# Create necessary directories
log_info "Creating directories..."
mkdir -p "$(dirname "$APP_DIR")"
mkdir -p "$APP_DIR"
mkdir -p "/home/flighttool/.npm"

# Fix ownership and permissions
log_info "Fixing ownership and permissions..."
chown -R flighttool:flighttool "$APP_DIR"
chown -R flighttool:flighttool "/home/flighttool"
chmod -R 755 "$APP_DIR"
chmod -R 755 "/home/flighttool"

# Fix specific file permissions
if [ -f "$APP_DIR/.env" ]; then
    chmod 644 "$APP_DIR/.env"
    chown flighttool:flighttool "$APP_DIR/.env"
fi

# Update or create systemd service
log_info "Creating/updating systemd service..."
cat > /etc/systemd/system/flighttool.service << EOF
[Unit]
Description=FlightTool Personal Flight Tracking Application
After=network.target

[Service]
Type=simple
User=flighttool
Group=flighttool
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=HOME=/home/flighttool
EnvironmentFile=$APP_DIR/.env
ExecStart=/usr/bin/npm start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10

# Security settings (relaxed for troubleshooting)
NoNewPrivileges=false
PrivateTmp=false
ProtectSystem=false
ProtectHome=false

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
log_info "Reloading systemd..."
systemctl daemon-reload

# Test if application exists
if [ -f "$APP_DIR/package.json" ]; then
    log_info "Application found, testing permissions..."
    
    # Test npm access as flighttool user
    if sudo -u flighttool bash -c "cd '$APP_DIR' && npm --version" &>/dev/null; then
        log_info "✓ npm access working"
    else
        log_warn "⚠ npm access issues, trying to fix..."
        
        # Fix npm permissions
        mkdir -p /home/flighttool/.npm
        chown -R flighttool:flighttool /home/flighttool/.npm
        
        # Test again
        if sudo -u flighttool bash -c "cd '$APP_DIR' && npm --version" &>/dev/null; then
            log_info "✓ npm access fixed"
        else
            log_error "✗ npm access still broken"
        fi
    fi
    
    # Install dependencies if missing
    if [ ! -d "$APP_DIR/node_modules" ]; then
        log_info "Installing dependencies..."
        sudo -u flighttool bash -c "cd '$APP_DIR' && npm install"
    fi
    
    # Test app startup
    log_info "Testing application startup..."
    if sudo -u flighttool bash -c "cd '$APP_DIR' && timeout 5 npm start" &>/dev/null; then
        log_info "✓ Application can start"
    else
        log_warn "⚠ Application startup test failed (may be normal for web servers)"
    fi
    
    # Enable and start service
    log_info "Starting FlightTool service..."
    systemctl enable flighttool
    systemctl start flighttool
    
    # Check service status
    sleep 3
    if systemctl is-active --quiet flighttool; then
        log_info "✓ FlightTool service is running successfully!"
        systemctl status flighttool --no-pager -l
    else
        log_error "✗ FlightTool service failed to start"
        echo
        echo "Service logs:"
        journalctl -u flighttool -n 20 --no-pager
        echo
        echo "Manual troubleshooting:"
        echo "sudo -u flighttool bash"
        echo "cd $APP_DIR"
        echo "npm start"
    fi
else
    log_warn "No package.json found in $APP_DIR"
    log_info "Make sure you have deployed the application first"
fi

log_info "Permission fix completed"
echo
echo "If issues persist, check:"
echo "1. Database connection (DATABASE_URL in .env)"
echo "2. Node.js and npm installation"
echo "3. Application logs: journalctl -u flighttool -f"