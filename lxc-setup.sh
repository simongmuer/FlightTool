#!/bin/bash
# FlightTool LXC Container Setup Script
# This script automates the deployment of FlightTool in an LXC container

set -e

# Configuration variables
CONTAINER_NAME="flighttool-app"
DB_PASSWORD=""
DOMAIN=""
EMAIL=""
APP_REPO=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script as root or with sudo"
        exit 1
    fi
}

# Get user input
get_user_input() {
    echo "FlightTool LXC Container Setup"
    echo "==============================="
    
    read -p "Enter database password for FlightTool: " -s DB_PASSWORD
    echo
    
    read -p "Enter your domain name (e.g., flighttool.example.com): " DOMAIN
    
    read -p "Enter your email for SSL certificate: " EMAIL
    
    read -p "Enter your FlightTool repository URL: " APP_REPO
    
    # Confirm settings
    echo
    echo "Configuration Summary:"
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL"
    echo "Repository: $APP_REPO"
    echo "Container: $CONTAINER_NAME"
    echo
    
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# Install LXD if not present
install_lxd() {
    if ! command -v lxc &> /dev/null; then
        log_info "Installing LXD..."
        apt update
        apt install -y lxd lxc-utils
        
        log_info "Initializing LXD (using defaults)..."
        lxd init --auto
        
        log_info "Adding current user to lxd group..."
        usermod -a -G lxd $SUDO_USER
    else
        log_info "LXD already installed"
    fi
}

# Create and configure container
create_container() {
    log_info "Creating LXC container: $CONTAINER_NAME"
    
    # Check if container already exists
    if lxc list | grep -q "$CONTAINER_NAME"; then
        log_warn "Container $CONTAINER_NAME already exists. Stopping and deleting..."
        lxc stop "$CONTAINER_NAME" --force || true
        lxc delete "$CONTAINER_NAME" --force || true
    fi
    
    # Create new container
    lxc launch ubuntu:22.04 "$CONTAINER_NAME"
    
    # Wait for container to be ready
    log_info "Waiting for container to start..."
    sleep 10
    
    # Update container
    log_info "Updating container packages..."
    lxc exec "$CONTAINER_NAME" -- apt update
    lxc exec "$CONTAINER_NAME" -- apt upgrade -y
}

# Install dependencies in container
install_dependencies() {
    log_info "Installing Node.js..."
    lxc exec "$CONTAINER_NAME" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    lxc exec "$CONTAINER_NAME" -- apt-get install -y nodejs
    
    log_info "Installing PostgreSQL..."
    lxc exec "$CONTAINER_NAME" -- apt-get install -y postgresql postgresql-contrib
    
    log_info "Installing additional tools..."
    lxc exec "$CONTAINER_NAME" -- apt-get install -y git curl wget nginx certbot python3-certbot-nginx
}

# Configure PostgreSQL
setup_database() {
    log_info "Configuring PostgreSQL..."
    
    lxc exec "$CONTAINER_NAME" -- systemctl start postgresql
    lxc exec "$CONTAINER_NAME" -- systemctl enable postgresql
    
    # Create database and user
    lxc exec "$CONTAINER_NAME" -- sudo -u postgres psql << EOF
CREATE DATABASE flighttool;
CREATE USER flighttool WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
ALTER USER flighttool CREATEDB;
\q
EOF

    # Configure PostgreSQL for local connections
    lxc exec "$CONTAINER_NAME" -- bash -c "echo 'local   all             flighttool                              md5' >> /etc/postgresql/*/main/pg_hba.conf"
    lxc exec "$CONTAINER_NAME" -- systemctl restart postgresql
}

# Deploy application
deploy_application() {
    log_info "Deploying FlightTool application..."
    
    # Create application directory
    lxc exec "$CONTAINER_NAME" -- mkdir -p /opt/flighttool
    
    # Clone repository
    if [ -n "$APP_REPO" ]; then
        lxc exec "$CONTAINER_NAME" -- git clone "$APP_REPO" /opt/flighttool
    else
        log_warn "No repository provided. You'll need to upload files manually to /opt/flighttool"
    fi
    
    # Create environment file
    lxc exec "$CONTAINER_NAME" -- bash -c "cat > /opt/flighttool/.env << EOF
NODE_ENV=production
DATABASE_URL=postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool
SESSION_SECRET=\$(openssl rand -base64 32)
PORT=3000
REPLIT_DOMAINS=$DOMAIN
EOF"
    
    # Install dependencies and build (if package.json exists)
    if lxc exec "$CONTAINER_NAME" -- test -f /opt/flighttool/package.json; then
        log_info "Installing all dependencies (including dev dependencies for build)..."
        lxc exec "$CONTAINER_NAME" -- bash -c "cd /opt/flighttool && npm install"
        
        log_info "Building application..."
        lxc exec "$CONTAINER_NAME" -- bash -c "cd /opt/flighttool && npm run build"
        
        log_info "Running database migrations..."
        lxc exec "$CONTAINER_NAME" -- bash -c "cd /opt/flighttool && npm run db:push"
        
        log_info "Cleaning dev dependencies..."
        lxc exec "$CONTAINER_NAME" -- bash -c "cd /opt/flighttool && npm prune --production"
    fi
    
    # Create application user
    lxc exec "$CONTAINER_NAME" -- useradd -r -s /bin/false flighttool
    lxc exec "$CONTAINER_NAME" -- chown -R flighttool:flighttool /opt/flighttool
}

# Create systemd service
create_service() {
    log_info "Creating systemd service..."
    
    lxc exec "$CONTAINER_NAME" -- bash -c "cat > /etc/systemd/system/flighttool.service << 'EOF'
[Unit]
Description=FlightTool Application
After=network.target postgresql.service

[Service]
Type=simple
User=flighttool
WorkingDirectory=/opt/flighttool
Environment=NODE_ENV=production
EnvironmentFile=/opt/flighttool/.env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/flighttool

[Install]
WantedBy=multi-user.target
EOF"
    
    lxc exec "$CONTAINER_NAME" -- systemctl daemon-reload
    lxc exec "$CONTAINER_NAME" -- systemctl enable flighttool
    lxc exec "$CONTAINER_NAME" -- systemctl start flighttool
}

# Configure Nginx
setup_nginx() {
    log_info "Configuring Nginx..."
    
    lxc exec "$CONTAINER_NAME" -- bash -c "cat > /etc/nginx/sites-available/flighttool << 'EOF'
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF"
    
    lxc exec "$CONTAINER_NAME" -- ln -sf /etc/nginx/sites-available/flighttool /etc/nginx/sites-enabled/
    lxc exec "$CONTAINER_NAME" -- rm -f /etc/nginx/sites-enabled/default
    
    lxc exec "$CONTAINER_NAME" -- nginx -t
    lxc exec "$CONTAINER_NAME" -- systemctl enable nginx
    lxc exec "$CONTAINER_NAME" -- systemctl restart nginx
}

# Configure networking
setup_networking() {
    log_info "Configuring container networking..."
    
    # Add port forwarding
    lxc config device add "$CONTAINER_NAME" http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
    lxc config device add "$CONTAINER_NAME" https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443
}

# Setup SSL certificate
setup_ssl() {
    if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
        log_info "Setting up SSL certificate with Let's Encrypt..."
        
        lxc exec "$CONTAINER_NAME" -- certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"
        
        # Setup auto-renewal
        lxc exec "$CONTAINER_NAME" -- bash -c "echo '0 2 * * * root certbot renew --quiet' >> /etc/crontab"
    else
        log_warn "Domain or email not provided. Skipping SSL setup."
    fi
}

# Set resource limits
set_limits() {
    log_info "Setting container resource limits..."
    
    lxc config set "$CONTAINER_NAME" limits.cpu 2
    lxc config set "$CONTAINER_NAME" limits.memory 4GB
    lxc config device override "$CONTAINER_NAME" root size=20GB
}

# Create backup script
create_backup_script() {
    log_info "Creating backup script..."
    
    cat > "/root/backup-flighttool.sh" << 'EOF'
#!/bin/bash
# FlightTool automated backup script

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/flighttool"
CONTAINER_NAME="flighttool-app"

mkdir -p $BACKUP_DIR

# Backup database
lxc exec $CONTAINER_NAME -- sudo -u postgres pg_dump flighttool > $BACKUP_DIR/db_$DATE.sql

# Backup container snapshot
lxc snapshot $CONTAINER_NAME daily-$DATE

# Clean old backups (keep 7 days)
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
lxc delete $CONTAINER_NAME/daily-$(date -d "7 days ago" +%Y%m%d_%H%M%S) 2>/dev/null || true

echo "Backup completed: $DATE"
EOF
    
    chmod +x /root/backup-flighttool.sh
    
    # Add to crontab for daily backups
    echo "0 2 * * * /root/backup-flighttool.sh" >> /etc/crontab
}

# Print final status
print_status() {
    echo
    log_info "FlightTool LXC container deployment completed!"
    echo
    echo "Container Information:"
    echo "====================="
    echo "Container name: $CONTAINER_NAME"
    echo "Domain: $DOMAIN"
    echo "Application URL: http://$DOMAIN (or https:// if SSL configured)"
    echo
    echo "Management Commands:"
    echo "==================="
    echo "View container status: lxc list"
    echo "Enter container: lxc shell $CONTAINER_NAME"
    echo "View app logs: lxc exec $CONTAINER_NAME -- journalctl -u flighttool -f"
    echo "Restart app: lxc exec $CONTAINER_NAME -- systemctl restart flighttool"
    echo "Stop container: lxc stop $CONTAINER_NAME"
    echo "Start container: lxc start $CONTAINER_NAME"
    echo
    echo "Backup script created at: /root/backup-flighttool.sh"
    echo "Daily backups configured for 2 AM"
    echo
    
    # Show service status
    log_info "Current service status:"
    lxc exec "$CONTAINER_NAME" -- systemctl status flighttool --no-pager -l
}

# Main execution
main() {
    log_info "Starting FlightTool LXC deployment..."
    
    check_root
    get_user_input
    install_lxd
    create_container
    install_dependencies
    setup_database
    deploy_application
    create_service
    setup_nginx
    setup_networking
    setup_ssl
    set_limits
    create_backup_script
    print_status
    
    log_info "Deployment complete! Your FlightTool application should now be accessible."
}

# Run main function
main "$@"