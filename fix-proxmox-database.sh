#!/bin/bash
# FlightTool Proxmox Database Configuration Fix
# This script fixes the empty DATABASE_URL issue on Proxmox deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root or with sudo"
    exit 1
fi

echo "FlightTool Proxmox Database Configuration Fix"
echo "============================================="
echo

# Detect if we're in a container or on the host
if [ -f "/proc/1/cgroup" ] && grep -q "lxc\|docker" /proc/1/cgroup; then
    ENVIRONMENT="container"
    APP_PATH="/home/flighttool/app"
else
    ENVIRONMENT="host"
    # Prompt for container ID
    read -p "Enter your FlightTool container ID [100]: " CONTAINER_ID
    CONTAINER_ID=${CONTAINER_ID:-100}
    APP_PATH="/home/flighttool/app"
fi

log_info "Detected environment: $ENVIRONMENT"

# Function to execute commands based on environment
execute_cmd() {
    if [ "$ENVIRONMENT" = "container" ]; then
        eval "$1"
    else
        pct exec "$CONTAINER_ID" -- bash -c "$1"
    fi
}

# Function to get user input for database configuration
get_database_config() {
    echo "Database Configuration Options:"
    echo "1. Use local PostgreSQL (recommended for Proxmox)"
    echo "2. Use external database (Neon, AWS RDS, etc.)"
    echo
    
    read -p "Choose option [1]: " DB_OPTION
    DB_OPTION=${DB_OPTION:-1}
    
    if [ "$DB_OPTION" = "1" ]; then
        # Local PostgreSQL setup
        read -p "Enter database password for user 'flighttool': " -s DB_PASSWORD
        echo
        DATABASE_URL="postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool"
    else
        # External database
        read -p "Enter complete DATABASE_URL: " DATABASE_URL
    fi
}

# Check PostgreSQL installation and status
check_postgresql() {
    log_step "Checking PostgreSQL installation..."
    
    # Fix locale issues before PostgreSQL operations
    execute_cmd "export DEBIAN_FRONTEND=noninteractive"
    execute_cmd "apt-get update && apt-get install -y locales"
    execute_cmd "locale-gen en_US.UTF-8"
    execute_cmd "update-locale LANG=en_US.UTF-8"
    execute_cmd "export LANG=en_US.UTF-8"
    execute_cmd "export LC_ALL=en_US.UTF-8"
    
    if execute_cmd "command -v psql > /dev/null"; then
        log_info "PostgreSQL is installed"
        
        if execute_cmd "systemctl is-active postgresql > /dev/null"; then
            log_info "PostgreSQL service is running"
        else
            log_warn "PostgreSQL service is not running, starting it..."
            execute_cmd "systemctl start postgresql"
            execute_cmd "systemctl enable postgresql"
        fi
    else
        log_info "Installing PostgreSQL..."
        execute_cmd "apt update"
        execute_cmd "DEBIAN_FRONTEND=noninteractive apt install -y postgresql postgresql-contrib locales"
        execute_cmd "systemctl start postgresql"
        execute_cmd "systemctl enable postgresql"
        
        # Wait for PostgreSQL to be ready
        sleep 5
    fi
    
    # Ensure PostgreSQL is actually ready
    execute_cmd "timeout 30 bash -c 'until pg_isready; do sleep 1; done'"
}

# Setup local PostgreSQL database
setup_local_database() {
    log_step "Setting up local PostgreSQL database..."
    
    # Extract password from DATABASE_URL
    DB_PASSWORD=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    
    if [ -z "$DB_PASSWORD" ]; then
        log_error "Could not extract password from DATABASE_URL"
        exit 1
    fi
    
    # Fix locale warnings first
    log_info "Configuring system locale..."
    execute_cmd "export DEBIAN_FRONTEND=noninteractive"
    execute_cmd "locale-gen en_US.UTF-8 || true"
    execute_cmd "update-locale LANG=en_US.UTF-8 || true"
    execute_cmd "export LANG=en_US.UTF-8"
    execute_cmd "export LC_ALL=en_US.UTF-8"
    
    log_info "Creating database and user..."
    
    # First, terminate any existing connections to the database
    execute_cmd "sudo -u postgres psql -c \"SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = 'flighttool' AND pid <> pg_backend_pid();\" || true"
    
    # Create database and user with proper error handling
    execute_cmd "sudo -u postgres psql << 'EOF'
-- Drop existing database and user if they exist
DROP DATABASE IF EXISTS flighttool;
DROP ROLE IF EXISTS flighttool;

-- Create new database and user
CREATE ROLE flighttool WITH LOGIN PASSWORD '$DB_PASSWORD';
ALTER ROLE flighttool CREATEDB;
CREATE DATABASE flighttool OWNER flighttool;
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
\\q
EOF"
    
    # Configure PostgreSQL for local connections
    log_info "Configuring PostgreSQL authentication..."
    execute_cmd "grep -q 'local.*flighttool.*md5' /etc/postgresql/*/main/pg_hba.conf || echo 'local   all             flighttool                              md5' >> /etc/postgresql/*/main/pg_hba.conf"
    execute_cmd "systemctl restart postgresql"
    
    # Test database connection
    log_info "Testing database connection..."
    if execute_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c 'SELECT 1;' > /dev/null"; then
        log_info "Database connection successful"
    else
        log_error "Database connection failed"
        exit 1
    fi
}

# Update application environment
update_app_environment() {
    log_step "Updating application environment..."
    
    # Check if app directory exists
    if ! execute_cmd "test -d $APP_PATH"; then
        log_error "Application directory not found: $APP_PATH"
        exit 1
    fi
    
    # Backup existing .env file
    if execute_cmd "test -f $APP_PATH/.env"; then
        execute_cmd "cp $APP_PATH/.env $APP_PATH/.env.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing .env file"
    fi
    
    # Generate session secret
    SESSION_SECRET=$(openssl rand -base64 32)
    
    # Create new .env file
    execute_cmd "cat > $APP_PATH/.env << 'EOF'
# FlightTool Environment Configuration
NODE_ENV=production
PORT=3000

# Database Configuration
DATABASE_URL=$DATABASE_URL

# Session Configuration
SESSION_SECRET=$SESSION_SECRET

# Development mode configuration (for offline auth)
DEVELOPMENT_MODE=true

# Authentication Configuration (kept for compatibility)
REPLIT_DOMAINS=localhost
REPL_ID=flighttool-local
ISSUER_URL=https://replit.com/oidc
EOF"
    
    # Set proper file permissions
    execute_cmd "chown flighttool:flighttool $APP_PATH/.env"
    execute_cmd "chmod 644 $APP_PATH/.env"
    
    log_info "Environment file updated successfully"
}

# Run database migrations
run_migrations() {
    log_step "Running database migrations..."
    
    # Change to app directory and run migrations
    if execute_cmd "test -f $APP_PATH/package.json"; then
        log_info "Running database schema migration..."
        
        # Set environment and run migration
        execute_cmd "cd $APP_PATH && DATABASE_URL='$DATABASE_URL' npm run db:push" || {
            log_warn "Migration failed, trying alternative approach..."
            execute_cmd "cd $APP_PATH && su - flighttool -c 'cd $APP_PATH && DATABASE_URL=\"$DATABASE_URL\" npm run db:push'"
        }
        
        log_info "Database migration completed"
    else
        log_warn "package.json not found, skipping migrations"
    fi
}

# Restart application service
restart_application() {
    log_step "Restarting FlightTool service..."
    
    if execute_cmd "systemctl is-enabled flighttool > /dev/null 2>&1"; then
        execute_cmd "systemctl restart flighttool"
        sleep 5
        
        if execute_cmd "systemctl is-active flighttool > /dev/null"; then
            log_info "FlightTool service restarted successfully"
        else
            log_warn "Service restart may have issues, checking status..."
            execute_cmd "systemctl status flighttool --no-pager -l"
        fi
    else
        log_warn "FlightTool service not found or not enabled"
        log_info "You may need to create the systemd service manually"
    fi
}

# Test application
test_application() {
    log_step "Testing application..."
    
    # Wait for service to start
    sleep 10
    
    # Test health endpoint
    if execute_cmd "curl -f -s http://localhost:3000/api/health > /dev/null"; then
        log_info "Application is responding to health checks"
    else
        log_warn "Health check failed, but this might be normal if API routes aren't fully implemented"
    fi
    
    # Test database connection from app
    if execute_cmd "cd $APP_PATH && node -e \"
const { db } = require('./dist/db.js');
db.execute('SELECT 1 as test').then(() => {
  console.log('Database connection from app: SUCCESS');
  process.exit(0);
}).catch(err => {
  console.log('Database connection from app: FAILED');
  console.error(err.message);
  process.exit(1);
});\"" 2>/dev/null; then
        log_info "Application can connect to database"
    else
        log_warn "Database connection test from application failed"
    fi
}

# Display final status
show_final_status() {
    echo
    log_info "FlightTool Proxmox Database Configuration Complete!"
    echo
    echo "Configuration Summary:"
    echo "====================="
    echo "Database URL: $DATABASE_URL"
    echo "Environment: $ENVIRONMENT"
    if [ "$ENVIRONMENT" != "container" ]; then
        echo "Container ID: $CONTAINER_ID"
    fi
    echo "App Path: $APP_PATH"
    echo
    echo "Next Steps:"
    echo "==========="
    echo "1. Check service status: systemctl status flighttool"
    echo "2. View logs: journalctl -u flighttool -f"
    echo "3. Test database: psql '$DATABASE_URL' -c 'SELECT 1;'"
    echo "4. Access app: http://your-server-ip:3000"
    echo
    
    if execute_cmd "systemctl is-active flighttool > /dev/null"; then
        log_info "✓ FlightTool service is currently running"
    else
        log_warn "⚠ FlightTool service is not running - check systemctl status flighttool"
    fi
}

# Main execution
main() {
    log_info "Starting FlightTool database configuration fix..."
    
    get_database_config
    
    if [[ "$DATABASE_URL" == postgresql://flighttool:* ]]; then
        check_postgresql
        setup_local_database
    else
        log_info "Using external database, skipping local PostgreSQL setup"
    fi
    
    update_app_environment
    run_migrations
    restart_application
    test_application
    show_final_status
    
    echo
    log_info "Database configuration fix completed!"
}

# Run main function
main "$@"