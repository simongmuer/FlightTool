#!/bin/bash
# FlightTool Database Migration Script
# Creates all required database tables and schema

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "FlightTool Database Schema Migration"
echo "==================================="

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

# Get database credentials
log_step "Getting database configuration..."

if run_cmd "test -f /home/flighttool/app/.env"; then
    DB_URL=$(run_cmd "grep '^DATABASE_URL=' /home/flighttool/app/.env | cut -d'=' -f2-" || echo "")
    if [ -n "$DB_URL" ]; then
        log_info "Found DATABASE_URL in .env file"
        # Extract password from URL
        DB_PASSWORD=$(echo "$DB_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    else
        log_warn "DATABASE_URL not found in .env file"
        read -p "Enter database password for flighttool user: " -s DB_PASSWORD
        echo
        DB_URL="postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool"
    fi
else
    log_warn ".env file not found"
    read -p "Enter database password for flighttool user: " -s DB_PASSWORD
    echo
    DB_URL="postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool"
fi

# Test database connection
log_step "Testing database connection..."
if run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c 'SELECT 1;' > /dev/null 2>&1"; then
    log_info "✓ Database connection successful"
else
    log_error "✗ Database connection failed"
    log_error "Please ensure PostgreSQL is running and credentials are correct"
    exit 1
fi

# Create database schema manually (since npm might not be available or working)
log_step "Creating database schema..."

run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool << 'EOF'
-- Drop existing tables if they exist (in correct order due to foreign keys)
DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS airports CASCADE;
DROP TABLE IF EXISTS airlines CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;

-- Create sessions table (required for authentication)
CREATE TABLE sessions (
    sid VARCHAR PRIMARY KEY,
    sess JSONB NOT NULL,
    expire TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS IDX_session_expire ON sessions (expire);

-- Create users table
CREATE TABLE users (
    id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR UNIQUE,
    first_name VARCHAR,
    last_name VARCHAR,
    profile_image_url VARCHAR,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    username VARCHAR UNIQUE NOT NULL,
    password VARCHAR NOT NULL
);

-- Create airports table
CREATE TABLE airports (
    id SERIAL PRIMARY KEY,
    iata_code VARCHAR(3) UNIQUE,
    icao_code VARCHAR(4) UNIQUE,
    name VARCHAR NOT NULL,
    city VARCHAR,
    country VARCHAR,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create airlines table  
CREATE TABLE airlines (
    id SERIAL PRIMARY KEY,
    iata_code VARCHAR(2) UNIQUE,
    icao_code VARCHAR(3) UNIQUE,
    name VARCHAR NOT NULL,
    country VARCHAR,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create flights table
CREATE TABLE flights (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    flight_number VARCHAR,
    airline VARCHAR,
    from_airport VARCHAR NOT NULL,
    to_airport VARCHAR NOT NULL,
    departure_date DATE NOT NULL,
    departure_time TIME,
    arrival_date DATE,
    arrival_time TIME,
    aircraft_type VARCHAR,
    seat_number VARCHAR,
    flight_class VARCHAR,
    ticket_price DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'USD',
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_flights_user_id ON flights(user_id);
CREATE INDEX IF NOT EXISTS idx_flights_departure_date ON flights(departure_date);
CREATE INDEX IF NOT EXISTS idx_airports_iata ON airports(iata_code);
CREATE INDEX IF NOT EXISTS idx_airlines_iata ON airlines(iata_code);

-- Insert some basic airport data
INSERT INTO airports (iata_code, icao_code, name, city, country) VALUES
('JFK', 'KJFK', 'John F. Kennedy International Airport', 'New York', 'United States'),
('LAX', 'KLAX', 'Los Angeles International Airport', 'Los Angeles', 'United States'),
('LHR', 'EGLL', 'London Heathrow Airport', 'London', 'United Kingdom'),
('CDG', 'LFPG', 'Charles de Gaulle Airport', 'Paris', 'France'),
('NRT', 'RJAA', 'Narita International Airport', 'Tokyo', 'Japan'),
('DXB', 'OMDB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates'),
('SIN', 'WSSS', 'Singapore Changi Airport', 'Singapore', 'Singapore'),
('FRA', 'EDDF', 'Frankfurt Airport', 'Frankfurt', 'Germany'),
('AMS', 'EHAM', 'Amsterdam Airport Schiphol', 'Amsterdam', 'Netherlands'),
('SYD', 'YSSY', 'Sydney Kingsford Smith Airport', 'Sydney', 'Australia')
ON CONFLICT (iata_code) DO NOTHING;

-- Insert some basic airline data
INSERT INTO airlines (iata_code, icao_code, name, country) VALUES
('AA', 'AAL', 'American Airlines', 'United States'),
('UA', 'UAL', 'United Airlines', 'United States'),
('DL', 'DAL', 'Delta Air Lines', 'United States'),
('BA', 'BAW', 'British Airways', 'United Kingdom'),
('AF', 'AFR', 'Air France', 'France'),
('LH', 'DLH', 'Lufthansa', 'Germany'),
('EK', 'UAE', 'Emirates', 'United Arab Emirates'),
('SQ', 'SIA', 'Singapore Airlines', 'Singapore'),
('QF', 'QFA', 'Qantas', 'Australia'),
('JL', 'JAL', 'Japan Airlines', 'Japan')
ON CONFLICT (iata_code) DO NOTHING;

-- Grant all permissions to flighttool user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO flighttool;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO flighttool;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO flighttool;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flighttool;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flighttool;

\echo 'Database schema created successfully!'
EOF"

if [ $? -eq 0 ]; then
    log_info "✓ Database schema created successfully"
else
    log_error "✗ Failed to create database schema"
    exit 1
fi

# Verify tables were created
log_step "Verifying database tables..."
TABLES=$(run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -t -c \"SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;\"" | tr -d ' ')

log_info "Created tables:"
echo "$TABLES" | while read -r table; do
    if [ -n "$table" ]; then
        log_info "  ✓ $table"
    fi
done

# Test inserting a user (to verify permissions)
log_step "Testing database permissions..."
TEST_RESULT=$(run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -t -c \"INSERT INTO users (username, password, email) VALUES ('test_user', 'test_password', 'test@example.com') RETURNING id;\" 2>/dev/null || echo 'FAILED'")

if [[ "$TEST_RESULT" != "FAILED" && -n "$TEST_RESULT" ]]; then
    log_info "✓ Database permissions working correctly"
    # Clean up test user
    run_cmd "PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c \"DELETE FROM users WHERE username='test_user';\" > /dev/null 2>&1"
else
    log_error "✗ Database permissions test failed"
    exit 1
fi

# Update .env file with correct DATABASE_URL if needed
log_step "Updating environment configuration..."
if [ ! -f "/home/flighttool/app/.env" ] || ! run_cmd "grep -q '^DATABASE_URL=' /home/flighttool/app/.env"; then
    run_cmd "mkdir -p /home/flighttool/app"
    SESSION_SECRET=$(openssl rand -base64 32)
    
    run_cmd "cat > /home/flighttool/app/.env << 'EOF'
# FlightTool Environment Configuration
NODE_ENV=production
PORT=3000

# Database Configuration
DATABASE_URL=$DB_URL

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
    
    run_cmd "chown flighttool:flighttool /home/flighttool/app/.env" || run_cmd "chown 1000:1000 /home/flighttool/app/.env"
    run_cmd "chmod 644 /home/flighttool/app/.env"
    log_info "✓ Environment file updated"
fi

# Restart FlightTool service
log_step "Restarting FlightTool service..."
if run_cmd "systemctl is-enabled flighttool > /dev/null 2>&1"; then
    run_cmd "systemctl restart flighttool"
    sleep 5
    
    if run_cmd "systemctl is-active flighttool > /dev/null"; then
        log_info "✓ FlightTool service restarted successfully"
    else
        log_warn "Service restart may have issues"
        run_cmd "systemctl status flighttool --no-pager -l | tail -20"
    fi
else
    log_warn "FlightTool systemd service not found"
fi

# Final verification
log_step "Final verification..."
echo
echo "Migration Summary:"
echo "=================="
echo "Database: flighttool"
echo "User: flighttool"
echo "Tables created: users, flights, airports, airlines, sessions"
echo "Sample data: Basic airports and airlines added"
echo
echo "Test Commands:"
echo "=============="
echo "Check tables: PGPASSWORD='$DB_PASSWORD' psql -h localhost -U flighttool -d flighttool -c '\\dt'"
echo "Check service: systemctl status flighttool"
echo "View logs: journalctl -u flighttool -f"
echo "Test app: curl http://localhost:3000/api/register -X POST -H 'Content-Type: application/json' -d '{\"username\":\"testuser\",\"password\":\"test123\",\"email\":\"test@test.com\"}'"
echo

log_info "Database migration completed successfully!"
log_info "Your FlightTool application should now have all required database tables."