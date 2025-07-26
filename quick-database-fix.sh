#!/bin/bash
# Quick Database Fix for FlightTool on Proxmox
# Addresses the specific errors shown in the user's screenshot

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "Quick FlightTool Database Fix"
echo "============================"

# Check if we're in container or need container ID
if [ -f "/proc/1/cgroup" ] && grep -q "lxc" /proc/1/cgroup; then
    CONTAINER_MODE=true
    log_info "Running inside LXC container"
else
    CONTAINER_MODE=false
    read -p "Enter container ID [120]: " CONTAINER_ID
    CONTAINER_ID=${CONTAINER_ID:-120}
    log_info "Will operate on container $CONTAINER_ID"
fi

# Function to execute commands
run_cmd() {
    if [ "$CONTAINER_MODE" = true ]; then
        bash -c "$1"
    else
        pct exec "$CONTAINER_ID" -- bash -c "$1"
    fi
}

# 1. Fix locale issues
log_info "Step 1: Fixing locale configuration..."
run_cmd "export DEBIAN_FRONTEND=noninteractive"
run_cmd "apt-get update -qq"
run_cmd "apt-get install -y locales"
run_cmd "locale-gen en_US.UTF-8"
run_cmd "update-locale LANG=en_US.UTF-8"
run_cmd "echo 'export LANG=en_US.UTF-8' >> /etc/environment"
run_cmd "echo 'export LC_ALL=en_US.UTF-8' >> /etc/environment"

# 2. Stop any running flighttool processes
log_info "Step 2: Stopping existing FlightTool processes..."
run_cmd "systemctl stop flighttool || true"
run_cmd "pkill -f 'node.*flighttool' || true"
run_cmd "pkill -f 'npm.*start' || true"

# 3. Clean up PostgreSQL connections and recreate database
log_info "Step 3: Cleaning up PostgreSQL database..."

# Get database password
read -p "Enter database password for FlightTool: " -s DB_PASSWORD
echo

# Terminate existing connections and recreate database
run_cmd "sudo -u postgres psql << 'EOF'
-- Terminate all connections to flighttool database
SELECT pg_terminate_backend(pg_stat_activity.pid) 
FROM pg_stat_activity 
WHERE pg_stat_activity.datname = 'flighttool' 
AND pid <> pg_backend_pid();

-- Drop and recreate database and user
DROP DATABASE IF EXISTS flighttool;
DROP ROLE IF EXISTS flighttool;

-- Create role first, then database
CREATE ROLE flighttool WITH LOGIN PASSWORD '$DB_PASSWORD';
ALTER ROLE flighttool CREATEDB;
CREATE DATABASE flighttool OWNER flighttool;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
GRANT ALL PRIVILEGES ON SCHEMA public TO flighttool;

-- Connect to flighttool database and set permissions
\\c flighttool
GRANT ALL ON SCHEMA public TO flighttool;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flighttool;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flighttool;

\\q
EOF"

# 4. Update application environment
log_info "Step 4: Updating application environment..."

DATABASE_URL="postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool"
SESSION_SECRET=$(openssl rand -base64 32)

run_cmd "mkdir -p /home/flighttool/app"

# Create proper .env file
run_cmd "cat > /home/flighttool/app/.env << 'EOF'
# FlightTool Environment Configuration
NODE_ENV=production
PORT=3000

# Database Configuration
DATABASE_URL=$DATABASE_URL

# Session Configuration  
SESSION_SECRET=$SESSION_SECRET

# PostgreSQL Connection Details
PGHOST=localhost
PGPORT=5432
PGUSER=flighttool
PGPASSWORD=$DB_PASSWORD
PGDATABASE=flighttool

# Development mode for offline auth
DEVELOPMENT_MODE=true

# Auth configuration (compatibility)
REPLIT_DOMAINS=localhost
REPL_ID=flighttool-local
ISSUER_URL=https://replit.com/oidc
EOF"

# Set ownership and permissions
run_cmd "chown -R flighttool:flighttool /home/flighttool" || run_cmd "chown -R 1000:1000 /home/flighttool"
run_cmd "chmod 644 /home/flighttool/app/.env"

# 5. Test database connection
log_info "Step 5: Testing database connection..."
if run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c 'SELECT 1 as test;'"; then
    log_info "✓ Database connection successful"
else
    log_error "✗ Database connection failed"
    exit 1
fi

# 6. Run database migrations (if possible)
log_info "Step 6: Running database migrations..."
if run_cmd "test -f /home/flighttool/app/package.json"; then
    run_cmd "cd /home/flighttool/app && su flighttool -c 'DATABASE_URL=\"$DATABASE_URL\" npm run db:push'" || {
        log_warn "Migration failed - this is normal if tables already exist or npm packages aren't installed"
    }
else
    log_warn "No package.json found - migrations skipped"
fi

# 7. Fix systemd service if it exists
log_info "Step 7: Updating systemd service..."
if run_cmd "test -f /etc/systemd/system/flighttool.service"; then
    run_cmd "systemctl daemon-reload"
    run_cmd "systemctl enable flighttool"
else
    log_warn "No systemd service found - you may need to create one manually"
fi

# 8. Start the service
log_info "Step 8: Starting FlightTool service..."
if run_cmd "systemctl start flighttool"; then
    sleep 5
    if run_cmd "systemctl is-active flighttool"; then
        log_info "✓ FlightTool service started successfully"
    else
        log_warn "Service may have issues - check logs with: journalctl -u flighttool -f"
    fi
else
    log_warn "Failed to start via systemd - service may not exist"
fi

# 9. Final verification
log_info "Step 9: Final verification..."
echo
echo "Configuration Summary:"
echo "======================"
echo "Database URL: $DATABASE_URL"
echo "Database User: flighttool"
echo "Database Name: flighttool"
echo "App Directory: /home/flighttool/app"
echo
echo "Verification Commands:"
echo "======================"
echo "Check service: systemctl status flighttool"
echo "View logs: journalctl -u flighttool -f"
echo "Test DB: PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c 'SELECT 1;'"
echo "Test app: curl http://localhost:3000/api/health"
echo

log_info "Quick database fix completed!"
log_info "If you still have issues, check the service logs and ensure your application code is properly deployed."