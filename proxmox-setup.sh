#!/bin/bash
# FlightTool Proxmox VE LXC Container Setup Script
# This script automates the deployment of FlightTool in a Proxmox LXC container

set -e

# Configuration variables
CONTAINER_ID="100"
CONTAINER_NAME="flighttool-app"
TEMPLATE="ubuntu-22.04-standard"
STORAGE="local-lvm"
MEMORY="4096"
SWAP="2048"
CORES="2"
DISK_SIZE="20"
BRIDGE="vmbr0"
DB_PASSWORD=""
DOMAIN=""
EMAIL=""
APP_REPO=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running on Proxmox
check_proxmox() {
    if ! command -v pct &> /dev/null; then
        log_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script as root"
        exit 1
    fi
}

# Get user input
get_user_input() {
    echo "FlightTool Proxmox VE LXC Container Setup"
    echo "========================================"
    echo
    
    # Container configuration
    read -p "Container ID [${CONTAINER_ID}]: " input
    CONTAINER_ID=${input:-$CONTAINER_ID}
    
    read -p "Container name [${CONTAINER_NAME}]: " input
    CONTAINER_NAME=${input:-$CONTAINER_NAME}
    
    read -p "Memory (MiB) [${MEMORY}]: " input
    MEMORY=${input:-$MEMORY}
    
    read -p "CPU cores [${CORES}]: " input
    CORES=${input:-$CORES}
    
    read -p "Disk size (GB) [${DISK_SIZE}]: " input
    DISK_SIZE=${input:-$DISK_SIZE}
    
    read -p "Network bridge [${BRIDGE}]: " input
    BRIDGE=${input:-$BRIDGE}
    
    echo
    read -p "Use DHCP for IP assignment? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        NETWORK_CONFIG="name=eth0,bridge=${BRIDGE},ip=dhcp"
    else
        read -p "Enter static IP (format: 192.168.1.100/24): " STATIC_IP
        read -p "Enter gateway IP: " GATEWAY_IP
        NETWORK_CONFIG="name=eth0,bridge=${BRIDGE},ip=${STATIC_IP},gw=${GATEWAY_IP}"
    fi
    
    # Application configuration
    echo
    read -p "Enter database password for FlightTool: " -s DB_PASSWORD
    echo
    
    read -p "Enter your domain name (optional): " DOMAIN
    
    if [ -n "$DOMAIN" ]; then
        read -p "Enter your email for SSL certificate: " EMAIL
    fi
    
    read -p "Enter your FlightTool repository URL: " APP_REPO
    
    # Confirm settings
    echo
    echo "Configuration Summary:"
    echo "====================="
    echo "Container ID: $CONTAINER_ID"
    echo "Container Name: $CONTAINER_NAME"
    echo "Memory: ${MEMORY} MiB"
    echo "CPU Cores: $CORES"
    echo "Disk Size: ${DISK_SIZE} GB"
    echo "Network: $NETWORK_CONFIG"
    echo "Domain: ${DOMAIN:-"Not specified"}"
    echo "Repository: ${APP_REPO:-"Manual upload required"}"
    echo
    
    read -p "Proceed with container creation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# Download LXC template if not exists
download_template() {
    log_step "Checking for Ubuntu 22.04 template..."
    
    if ! pveam list local | grep -q "$TEMPLATE"; then
        log_info "Downloading Ubuntu 22.04 template..."
        pveam update
        pveam download local "$TEMPLATE"
    else
        log_info "Template already available"
    fi
}

# Create LXC container
create_container() {
    log_step "Creating LXC container..."
    
    # Check if container ID already exists
    if pct list | awk '{print $1}' | grep -q "^${CONTAINER_ID}$"; then
        log_warn "Container ID $CONTAINER_ID already exists"
        read -p "Stop and destroy existing container? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pct stop "$CONTAINER_ID" || true
            pct destroy "$CONTAINER_ID" || true
        else
            log_error "Cannot proceed with existing container ID"
            exit 1
        fi
    fi
    
    # Create container
    log_info "Creating container with ID $CONTAINER_ID..."
    pct create "$CONTAINER_ID" "local:vztmpl/${TEMPLATE}_amd64.tar.zst" \
        --hostname "$CONTAINER_NAME" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --cores "$CORES" \
        --rootfs "${STORAGE}:${DISK_SIZE}" \
        --net0 "$NETWORK_CONFIG" \
        --features nesting=1 \
        --unprivileged 1 \
        --password \
        --start 1
    
    # Wait for container to start
    log_info "Waiting for container to start..."
    sleep 30
    
    # Verify container is running
    if ! pct status "$CONTAINER_ID" | grep -q "running"; then
        log_error "Container failed to start"
        exit 1
    fi
    
    log_info "Container created and started successfully"
}

# Update container system
update_container() {
    log_step "Updating container system..."
    
    pct exec "$CONTAINER_ID" -- apt update
    pct exec "$CONTAINER_ID" -- apt upgrade -y
    pct exec "$CONTAINER_ID" -- apt install -y curl wget git sudo nano htop
}

# Install Node.js
install_nodejs() {
    log_step "Installing Node.js 18..."
    
    pct exec "$CONTAINER_ID" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
    pct exec "$CONTAINER_ID" -- apt-get install -y nodejs
    
    # Verify installation
    NODE_VERSION=$(pct exec "$CONTAINER_ID" -- node --version)
    NPM_VERSION=$(pct exec "$CONTAINER_ID" -- npm --version)
    log_info "Node.js $NODE_VERSION and npm $NPM_VERSION installed"
}

# Install and configure PostgreSQL
install_postgresql() {
    log_step "Installing and configuring PostgreSQL..."
    
    pct exec "$CONTAINER_ID" -- apt install -y postgresql postgresql-contrib
    pct exec "$CONTAINER_ID" -- systemctl start postgresql
    pct exec "$CONTAINER_ID" -- systemctl enable postgresql
    
    # Create database and user
    pct exec "$CONTAINER_ID" -- sudo -u postgres psql << EOF
CREATE DATABASE flighttool;
CREATE USER flighttool WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
ALTER USER flighttool CREATEDB;
\q
EOF
    
    # Configure PostgreSQL for local connections
    pct exec "$CONTAINER_ID" -- bash -c "echo 'local   all             flighttool                              md5' >> /etc/postgresql/*/main/pg_hba.conf"
    pct exec "$CONTAINER_ID" -- systemctl restart postgresql
    
    log_info "PostgreSQL configured successfully"
}

# Install Nginx
install_nginx() {
    log_step "Installing Nginx..."
    
    pct exec "$CONTAINER_ID" -- apt install -y nginx
    pct exec "$CONTAINER_ID" -- systemctl enable nginx
}

# Create application user
create_app_user() {
    log_step "Creating application user..."
    
    pct exec "$CONTAINER_ID" -- useradd -m -s /bin/bash flighttool
    pct exec "$CONTAINER_ID" -- usermod -aG sudo flighttool
}

# Deploy application
deploy_application() {
    log_step "Deploying FlightTool application..."
    
    # Create application directory
    pct exec "$CONTAINER_ID" -- mkdir -p /home/flighttool/app
    
    if [ -n "$APP_REPO" ]; then
        log_info "Cloning repository..."
        pct exec "$CONTAINER_ID" -- git clone "$APP_REPO" /home/flighttool/app
    else
        log_warn "No repository specified. You'll need to upload files manually to /home/flighttool/app"
        return 0
    fi
    
    # Copy build script to container
    log_info "Copying production build script..."
    if [ -f "build-production.sh" ]; then
        pct push "$CONTAINER_ID" build-production.sh /home/flighttool/app/build-production.sh
        pct exec "$CONTAINER_ID" -- chmod +x /home/flighttool/app/build-production.sh
    else
        log_warn "build-production.sh not found locally, creating fallback build script..."
        create_fallback_build_script
    fi
    
    # Create environment file
    log_info "Creating environment configuration..."
    pct exec "$CONTAINER_ID" -- bash -c "cat > /home/flighttool/app/.env << 'EOF'
NODE_ENV=production
DATABASE_URL=postgresql://flighttool:$DB_PASSWORD@localhost:5432/flighttool
SESSION_SECRET=\$(openssl rand -base64 32)
PORT=3000
REPLIT_DOMAINS=${DOMAIN:-localhost}
EOF"
    
    # Install dependencies and build
    if pct exec "$CONTAINER_ID" -- test -f /home/flighttool/app/package.json; then
        log_info "Installing all dependencies (including dev dependencies for build)..."
        pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm install"
        
        log_info "Building application for production..."
        pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && chmod +x build-production.sh"
        # Try the production build script, fall back to simple build if it fails
        if ! pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && DATABASE_URL=\$DATABASE_URL CLEAN_DEV_DEPS=true timeout 300 ./build-production.sh"; then
            log_warn "Production build failed, using simplified build process..."
            create_simple_production_build
        fi
    fi
    
    # Set proper ownership and permissions with comprehensive fixes
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool
    pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool
    pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool/app
    
    # Fix specific file permissions
    if pct exec "$CONTAINER_ID" -- test -f /home/flighttool/app/.env; then
        pct exec "$CONTAINER_ID" -- chmod 644 /home/flighttool/app/.env
        pct exec "$CONTAINER_ID" -- chown flighttool:flighttool /home/flighttool/app/.env
    fi
    
    # Fix npm global directory permissions
    pct exec "$CONTAINER_ID" -- mkdir -p /home/flighttool/.npm
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/.npm
}

# Comprehensive database setup with error handling
setup_database_comprehensive() {
    log_step "Comprehensive database setup with error handling..."
    
    # Fix locale issues first
    pct exec "$CONTAINER_ID" -- export DEBIAN_FRONTEND=noninteractive
    pct exec "$CONTAINER_ID" -- apt-get update -qq
    pct exec "$CONTAINER_ID" -- apt-get install -y locales
    pct exec "$CONTAINER_ID" -- locale-gen en_US.UTF-8
    pct exec "$CONTAINER_ID" -- update-locale LANG=en_US.UTF-8
    pct exec "$CONTAINER_ID" -- bash -c "echo 'export LANG=en_US.UTF-8' >> /etc/environment"
    pct exec "$CONTAINER_ID" -- bash -c "echo 'export LC_ALL=en_US.UTF-8' >> /etc/environment"
    
    # Stop any existing processes
    pct exec "$CONTAINER_ID" -- systemctl stop flighttool || true
    pct exec "$CONTAINER_ID" -- pkill -f 'node.*flighttool' || true
    
    # Terminate database connections and recreate
    pct exec "$CONTAINER_ID" -- sudo -u postgres psql << EOF
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

-- Create complete database schema
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

-- Insert basic airport data
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

-- Insert basic airline data
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

\\q
EOF
    
    log_info "Database setup completed successfully"
}

# Create fallback build script if needed
create_fallback_build_script() {
    log_info "Creating production build script in container..."
    pct exec "$CONTAINER_ID" -- bash -c "cat > /home/flighttool/app/build-production.sh << 'EOFSCRIPT'
#!/bin/bash
# Production build script for FlightTool
set -e

echo \"Building FlightTool for production...\"

# Clean existing build
rm -rf dist

# Install dependencies
npm install

# Build frontend
npm run build 2>/dev/null

# Create production server that doesn't import Vite
mkdir -p dist

cat > dist/index.js << 'EOF'
import express from \"express\";
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Simple logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on(\"finish\", () => {
    const duration = Date.now() - start;
    if (req.path.startsWith(\"/api\")) {
      console.log(\`\${new Date().toLocaleTimeString()} [express] \${req.method} \${req.path} \${res.statusCode} in \${duration}ms\`);
    }
  });
  next();
});

// Import routes
import('./routes.js').then(({ registerRoutes }) => {
  registerRoutes(app).then((server) => {
    const distPath = resolve(__dirname, \"public\");
    
    if (!fs.existsSync(distPath)) {
      throw new Error(\`Build directory not found: \${distPath}\`);
    }
    
    app.use(express.static(distPath));
    app.get(\"*\", (req, res) => {
      res.sendFile(resolve(distPath, \"index.html\"));
    });
    
    const port = parseInt(process.env.PORT || '3000', 10);
    server.listen(port, \"0.0.0.0\", () => {
      console.log(\`\${new Date().toLocaleTimeString()} [express] serving on port \${port}\`);
    });
  });
}).catch(err => {
  console.error('Server startup failed:', err);
  process.exit(1);
});
EOF

# Build server modules
npx esbuild server/routes.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/routes.js --external:express --external:openid-client --external:passport* --external:drizzle-orm --external:postgres --external:connect-pg-simple --external:express-session --external:memoizee --external:multer --external:csv-parser
npx esbuild server/storage.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/storage.js --external:drizzle-orm --external:postgres
npx esbuild server/db.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/db.js --external:drizzle-orm --external:postgres --external:@neondatabase/serverless
npx esbuild server/replitAuth.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/replitAuth.js --external:openid-client --external:passport* --external:express-session --external:connect-pg-simple --external:memoizee

# Copy shared schema
mkdir -p dist/shared
cp shared/schema.ts dist/shared/

# Run migrations
if [ -n \"\$DATABASE_URL\" ]; then
  npm run db:push
fi

# Clean dev dependencies if requested
if [ \"\$CLEAN_DEV_DEPS\" = \"true\" ]; then
  npm prune --production
fi

echo \"Production build completed successfully\"
EOFSCRIPT"
    
    pct exec "$CONTAINER_ID" -- chmod +x /home/flighttool/app/build-production.sh
}

# Create simple production build without complex dependencies
create_simple_production_build() {
    log_info "Creating simplified production build..."
    
    pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && rm -rf dist && mkdir -p dist"
    
    # Build frontend only
    pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm run build"
    
    # Create simple static server
    pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > dist/index.js << 'EOFSIMPLE'
import express from \"express\";
import { fileURLToPath } from \"url\";
import { dirname, resolve } from \"path\";
import fs from \"fs\";
import { createServer } from \"http\";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on(\"finish\", () => {
    const duration = Date.now() - start;
    if (req.path.startsWith(\"/api\")) {
      console.log(\`\${new Date().toLocaleTimeString()} [express] \${req.method} \${req.path} \${res.statusCode} in \${duration}ms\`);
    }
  });
  next();
});

// Serve static files
const distPath = resolve(__dirname, \"public\");
if (fs.existsSync(distPath)) {
  app.use(express.static(distPath));
  app.get(\"*\", (req, res) => {
    res.sendFile(resolve(distPath, \"index.html\"));
  });
} else {
  app.get(\"*\", (req, res) => {
    res.status(503).send(\"Frontend build not available\");
  });
}

const httpServer = createServer(app);
const port = parseInt(process.env.PORT || \"3000\", 10);
httpServer.listen(port, \"0.0.0.0\", () => {
  console.log(\`\${new Date().toLocaleTimeString()} [express] serving on port \${port}\`);
});
EOFSIMPLE"
    
    log_info "Simple build completed - serving frontend only"
}

# Create systemd service
create_systemd_service() {
    log_step "Creating systemd service..."
    
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
ExecStart=/usr/bin/node dist/index.js
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
EOF"
    
    # Ensure proper ownership and permissions after service file creation
    pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/app
    pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool/app
    pct exec "$CONTAINER_ID" -- chmod 644 /home/flighttool/app/.env 2>/dev/null || true
    
    pct exec "$CONTAINER_ID" -- systemctl daemon-reload
    pct exec "$CONTAINER_ID" -- systemctl enable flighttool
    pct exec "$CONTAINER_ID" -- systemctl start flighttool
    
    # Wait for service to start
    sleep 10
    
    # Check service status
    if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet flighttool; then
        log_info "FlightTool service started successfully"
    else
        log_warn "FlightTool service may have issues. Check logs with: pct exec $CONTAINER_ID -- journalctl -u flighttool"
    fi
}

# Configure Nginx
configure_nginx() {
    log_step "Configuring Nginx reverse proxy..."
    
    pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/nginx/sites-available/flighttool << 'EOF'
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=login:10m rate=1r/s;

# Upstream backend
upstream flighttool_backend {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name ${DOMAIN:-_};

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";

    # Rate limiting for API endpoints
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    # Rate limiting for auth endpoints
    location /api/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Main application
    location / {
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # Health check
    location /health {
        access_log off;
        return 200 \"healthy\\n\";
        add_header Content-Type text/plain;
    }
}
EOF"
    
    pct exec "$CONTAINER_ID" -- ln -sf /etc/nginx/sites-available/flighttool /etc/nginx/sites-enabled/
    pct exec "$CONTAINER_ID" -- rm -f /etc/nginx/sites-enabled/default
    
    # Test and start Nginx
    pct exec "$CONTAINER_ID" -- nginx -t
    pct exec "$CONTAINER_ID" -- systemctl start nginx
    pct exec "$CONTAINER_ID" -- systemctl reload nginx
}

# Setup SSL if domain provided
setup_ssl() {
    if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
        log_step "Setting up SSL certificate..."
        
        pct exec "$CONTAINER_ID" -- apt install -y certbot python3-certbot-nginx
        pct exec "$CONTAINER_ID" -- certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"
        
        # Setup auto-renewal
        pct exec "$CONTAINER_ID" -- bash -c "echo '0 2 * * * root certbot renew --quiet --deploy-hook \"systemctl reload nginx\"' >> /etc/crontab"
        
        log_info "SSL certificate configured for $DOMAIN"
    else
        log_info "Skipping SSL setup (no domain specified)"
    fi
}

# Configure firewall
configure_firewall() {
    log_step "Configuring container firewall..."
    
    pct exec "$CONTAINER_ID" -- apt install -y ufw
    pct exec "$CONTAINER_ID" -- ufw allow 22/tcp
    pct exec "$CONTAINER_ID" -- ufw allow 80/tcp
    pct exec "$CONTAINER_ID" -- ufw allow 443/tcp
    pct exec "$CONTAINER_ID" -- ufw --force enable
}

# Create backup script
create_backup_script() {
    log_step "Creating backup configuration..."
    
    # Create backup script on Proxmox host
    cat > "/usr/local/bin/backup-flighttool.sh" << EOF
#!/bin/bash
# FlightTool Proxmox backup script

DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/lib/vz/dump"
CONTAINER_ID="$CONTAINER_ID"

# Create container backup
vzdump "\$CONTAINER_ID" --storage local --mode snapshot --compress lzo --quiet 1

# Backup database separately
pct exec "\$CONTAINER_ID" -- sudo -u postgres pg_dump flighttool > "\$BACKUP_DIR/flighttool-db-\$DATE.sql"

# Clean old database backups (keep 7 days)
find "\$BACKUP_DIR" -name "flighttool-db-*.sql" -mtime +7 -delete

echo "Backup completed: \$DATE"
EOF
    
    chmod +x /usr/local/bin/backup-flighttool.sh
    
    # Add to crontab for daily backups
    echo "0 2 * * * root /usr/local/bin/backup-flighttool.sh" >> /etc/crontab
    
    log_info "Backup script created and scheduled"
}

# Get container IP
get_container_ip() {
    local ip
    ip=$(pct exec "$CONTAINER_ID" -- hostname -I | awk '{print $1}')
    echo "$ip"
}

# Print final status
print_status() {
    local container_ip
    container_ip=$(get_container_ip)
    
    echo
    log_info "FlightTool Proxmox VE deployment completed successfully!"
    echo
    echo "Container Information:"
    echo "====================="
    echo "Container ID: $CONTAINER_ID"
    echo "Container Name: $CONTAINER_NAME"
    echo "IP Address: $container_ip"
    echo "Domain: ${DOMAIN:-"Not configured"}"
    echo "Application URL: http://${DOMAIN:-$container_ip}"
    
    if [ -n "$DOMAIN" ]; then
        echo "HTTPS URL: https://$DOMAIN"
    fi
    
    echo
    echo "Proxmox Management:"
    echo "=================="
    echo "View in web interface: Proxmox VE → Node → $CONTAINER_ID ($CONTAINER_NAME)"
    echo "Container console: pct enter $CONTAINER_ID"
    echo "Start container: pct start $CONTAINER_ID"
    echo "Stop container: pct stop $CONTAINER_ID"
    echo "Container logs: pct exec $CONTAINER_ID -- journalctl -u flighttool -f"
    echo
    echo "Backup Information:"
    echo "=================="
    echo "Backup script: /usr/local/bin/backup-flighttool.sh"
    echo "Scheduled: Daily at 2:00 AM"
    echo "Manual backup: vzdump $CONTAINER_ID --storage local"
    echo
    
    # Test application
    log_info "Testing application..."
    if pct exec "$CONTAINER_ID" -- curl -f -s http://localhost:3000/health > /dev/null; then
        log_info "✓ Application is responding correctly"
    else
        log_warn "⚠ Application may not be responding. Check logs: pct exec $CONTAINER_ID -- journalctl -u flighttool"
    fi
    
    # Show service status
    echo
    log_info "Service Status:"
    pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l | head -10
}

# Main execution
main() {
    log_info "Starting FlightTool Proxmox VE deployment..."
    
    check_proxmox
    get_user_input
    download_template
    create_container
    update_container
    install_nodejs
    install_postgresql
    install_nginx
    create_app_user
    setup_database_comprehensive
    deploy_application
    create_systemd_service
    configure_nginx
    setup_ssl
    configure_firewall
    create_backup_script
    print_status
    
    log_info "Deployment complete! Your FlightTool application is ready."
}

# Run main function
main "$@"