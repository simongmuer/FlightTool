# FlightTool Proxmox VE Deployment Guide

This guide explains how to deploy your FlightTool application on Proxmox VE using LXC containers. Proxmox VE provides enterprise-grade virtualization with excellent web management interface and clustering capabilities.

## Overview

Proxmox VE (Virtual Environment) is an open-source server virtualization management platform. This deployment uses LXC containers for optimal performance and resource efficiency while maintaining complete isolation.

## Prerequisites

### Proxmox VE Requirements
- **Proxmox VE 7.0+** installed and configured
- **4GB RAM minimum** allocated to the container (8GB recommended)
- **20GB storage minimum** for the container
- **Internet connectivity** for package downloads
- **Administrative access** to Proxmox web interface

### Network Requirements
- **Static IP** or DHCP reservation for the container
- **Firewall rules** allowing HTTP (80) and HTTPS (443)
- **DNS configuration** if using a domain name

## Container Creation in Proxmox

### 1. Download LXC Template

Via Proxmox Web Interface:
1. Navigate to **Datacenter** → **Node** → **Local** → **CT Templates**
2. Click **Templates** button
3. Download **Ubuntu 22.04** template
4. Wait for download to complete

Via CLI (SSH to Proxmox host):
```bash
# Download Ubuntu 22.04 LXC template
pveam update
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
```

### 2. Create LXC Container

#### Via Web Interface:
1. Click **Create CT** button
2. Configure as follows:

**General Tab:**
- **CT ID**: 100 (or next available)
- **Hostname**: flighttool-app
- **Password**: Set a strong root password
- **SSH public key**: Optional but recommended

**Template Tab:**
- **Storage**: local
- **Template**: ubuntu-22.04-standard

**Root Disk Tab:**
- **Storage**: local-lvm (or your preferred storage)
- **Disk size**: 20GB minimum

**CPU Tab:**
- **Cores**: 2 (adjust based on your hardware)
- **CPU limit**: Leave default
- **CPU units**: 1024

**Memory Tab:**
- **Memory (MiB)**: 4096 (4GB)
- **Swap (MiB)**: 2048

**Network Tab:**
- **Bridge**: vmbr0 (or your network bridge)
- **IPv4**: DHCP or static IP
- **IPv6**: auto (or disable if not needed)

**DNS Tab:**
- **Use host settings**: Checked
- Or specify custom DNS servers

**Confirm Tab:**
- Review settings and click **Finish**

#### Via CLI:
```bash
# Create LXC container using CLI
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname flighttool-app \
  --memory 4096 \
  --swap 2048 \
  --cores 2 \
  --rootfs local-lvm:20 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --password \
  --start 1
```

### 3. Container Configuration

Start the container and enter console:
```bash
# Start container
pct start 100

# Enter container console
pct enter 100
```

## Application Installation

### 4. System Update and Basic Setup
```bash
# Update system packages
apt update && apt upgrade -y

# Install essential tools
apt install -y curl wget git sudo nano htop

# Create application user
useradd -m -s /bin/bash flighttool
usermod -aG sudo flighttool
```

### 5. Install Node.js 18
```bash
# Add NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -

# Install Node.js
apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

### 6. Install and Configure PostgreSQL
```bash
# Install PostgreSQL
apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL
systemctl start postgresql
systemctl enable postgresql

# Create database and user
sudo -u postgres psql << 'EOF'
CREATE DATABASE flighttool;
CREATE USER flighttool WITH PASSWORD 'flighttool_secure_password_2024';
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
ALTER USER flighttool CREATEDB;
\q
EOF

# Configure PostgreSQL for local connections
echo "local   all             flighttool                              md5" >> /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql

# Test database connection
sudo -u postgres psql -c "\l"
```

### 7. Install Nginx
```bash
# Install Nginx
apt install -y nginx

# Enable Nginx
systemctl enable nginx
```

## Application Deployment

### 8. Deploy FlightTool Application
```bash
# Switch to application user
su - flighttool

# Create application directory
mkdir -p /home/flighttool/app
cd /home/flighttool/app

# Clone repository (replace with your actual repository)
git clone https://github.com/yourusername/flighttool.git .

# Install all dependencies (including dev dependencies needed for build)
npm install

# Create environment configuration
cat > .env << 'EOF'
NODE_ENV=production
DATABASE_URL=postgresql://flighttool:flighttool_secure_password_2024@localhost:5432/flighttool
SESSION_SECRET=$(openssl rand -base64 32)
PORT=3000
REPLIT_DOMAINS=your-domain.com
EOF

# Build application
npm run build

# Run database migrations (before removing dev dependencies)
npm run db:push

# Remove dev dependencies after build and migrations (optional, saves space)
npm prune --production

# Test application startup
npm start
# Press Ctrl+C to stop after verifying it starts correctly

# Exit back to root
exit
```

### 9. Create Systemd Service
```bash
# Create systemd service file
cat > /etc/systemd/system/flighttool.service << 'EOF'
[Unit]
Description=FlightTool Personal Flight Tracking Application
After=network.target postgresql.service

[Service]
Type=simple
User=flighttool
Group=flighttool
WorkingDirectory=/home/flighttool/app
Environment=NODE_ENV=production
EnvironmentFile=/home/flighttool/app/.env
ExecStart=/usr/bin/npm start
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/home/flighttool/app

# Resource limits
LimitNOFILE=65536
MemoryLimit=2G

[Install]
WantedBy=multi-user.target
EOF

# Set proper ownership and permissions
chown -R flighttool:flighttool /home/flighttool/app
chmod -R 755 /home/flighttool/app
chmod 644 /home/flighttool/app/.env

# Reload systemd and start service
systemctl daemon-reload
systemctl enable flighttool
systemctl start flighttool

# Check service status
systemctl status flighttool
```

### 10. Configure Nginx Reverse Proxy
```bash
# Create Nginx configuration
cat > /etc/nginx/sites-available/flighttool << 'EOF'
# FlightTool Nginx Configuration

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

# Upstream backend
upstream flighttool_backend {
    server 127.0.0.1:3000;
    keepalive 32;
}

# HTTP server (redirect to HTTPS in production)
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # For development, serve directly over HTTP
    # In production, uncomment the redirect below
    # return 301 https://$server_name$request_uri;

    # Rate limiting for API endpoints
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 60s;
        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
    }

    # Rate limiting for auth endpoints
    location /api/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Main application
    location / {
        proxy_pass http://flighttool_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Static assets with caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://flighttool_backend;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Cache-Status "STATIC";
    }
}

# HTTPS server (uncomment and configure for production)
# server {
#     listen 443 ssl http2;
#     server_name your-domain.com www.your-domain.com;
#
#     # SSL configuration
#     ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers off;
#
#     # Security headers
#     add_header X-Frame-Options DENY;
#     add_header X-Content-Type-Options nosniff;
#     add_header X-XSS-Protection "1; mode=block";
#     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
#
#     # Same location blocks as HTTP server above
#     # ...
# }
EOF

# Enable site and remove default
ln -sf /etc/nginx/sites-available/flighttool /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Start and enable Nginx
systemctl start nginx
systemctl enable nginx
```

## Proxmox-Specific Configuration

### 11. Container Resource Management

Via Proxmox Web Interface:
1. Navigate to **Container** → **Resources**
2. Adjust CPU, Memory, and Disk as needed
3. Click **Apply** to save changes

Via CLI:
```bash
# Set CPU cores
pct set 100 -cores 4

# Set memory
pct set 100 -memory 8192

# Set swap
pct set 100 -swap 4096

# Resize disk (if needed)
pct resize 100 rootfs +10G

# Set CPU limit (optional)
pct set 100 -cpulimit 2
```

### 12. Network Configuration

#### Static IP Configuration:
```bash
# Via Proxmox CLI
pct set 100 -net0 name=eth0,bridge=vmbr0,ip=192.168.1.100/24,gw=192.168.1.1

# Or edit network configuration inside container
nano /etc/netplan/00-installer-config.yaml
```

Example netplan configuration:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

Apply network changes:
```bash
netplan apply
```

### 13. Firewall Configuration

#### Proxmox Firewall (recommended):
1. Navigate to **Datacenter** → **Firewall**
2. Enable firewall for the datacenter
3. Go to **Container** → **Firewall** → **Rules**
4. Add rules:
   - **Direction**: IN, **Action**: ACCEPT, **Protocol**: TCP, **Dest. port**: 22 (SSH)
   - **Direction**: IN, **Action**: ACCEPT, **Protocol**: TCP, **Dest. port**: 80 (HTTP)
   - **Direction**: IN, **Action**: ACCEPT, **Protocol**: TCP, **Dest. port**: 443 (HTTPS)

#### Or use UFW inside container:
```bash
# Install and configure UFW
apt install -y ufw

# Allow SSH, HTTP, and HTTPS
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Enable firewall
ufw --force enable

# Check status
ufw status
```

## SSL Certificate Setup

### 14. Install Certbot and Configure SSL
```bash
# Install Certbot
apt install -y certbot python3-certbot-nginx

# Obtain SSL certificate (replace with your domain)
certbot --nginx -d your-domain.com -d www.your-domain.com

# Test certificate renewal
certbot renew --dry-run

# Set up automatic renewal
echo "0 2 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" >> /etc/crontab
```

## Backup and Monitoring

### 15. Proxmox Backup Configuration

#### Create Backup Job via Web Interface:
1. Navigate to **Datacenter** → **Backup**
2. Click **Add** to create new backup job
3. Configure:
   - **Node**: Select your node
   - **Storage**: Choose backup storage
   - **Schedule**: Daily at 2:00 AM
   - **Selection Mode**: Include selected VMs
   - **VM ID**: 100 (your container ID)
   - **Retention**: Keep 7 daily, 4 weekly, 6 monthly backups

#### Create Backup Job via CLI:
```bash
# Create backup job
cat > /etc/pve/vzdump.cron << 'EOF'
# Backup FlightTool container daily at 2 AM
0 2 * * * root vzdump 100 --storage local --mode snapshot --compress lzo --quiet 1
EOF

# Restart cron service
systemctl restart cron
```

### 16. Container Monitoring

#### Via Proxmox Web Interface:
- Monitor CPU, Memory, Network, and Disk usage in real-time
- View historical performance graphs
- Set up email alerts for resource thresholds

#### Install monitoring tools inside container:
```bash
# Install monitoring tools
apt install -y htop iotop netstat-nat

# Install log monitoring
apt install -y logwatch

# Configure logwatch for daily reports
echo "root: your-email@domain.com" >> /etc/aliases
newaliases
```

### 17. Application Health Monitoring
```bash
# Create health check script
cat > /usr/local/bin/flighttool-health.sh << 'EOF'
#!/bin/bash
# FlightTool health check script

HEALTH_URL="http://localhost:3000/api/health"
LOG_FILE="/var/log/flighttool-health.log"

if curl -f -s "$HEALTH_URL" > /dev/null; then
    echo "$(date): FlightTool is healthy" >> "$LOG_FILE"
else
    echo "$(date): FlightTool health check failed, restarting service" >> "$LOG_FILE"
    systemctl restart flighttool
fi
EOF

chmod +x /usr/local/bin/flighttool-health.sh

# Add to crontab for every 5 minutes
echo "*/5 * * * * root /usr/local/bin/flighttool-health.sh" >> /etc/crontab
```

## Performance Optimization

### 18. Database Optimization for Proxmox
```bash
# Optimize PostgreSQL for container environment
cat >> /etc/postgresql/*/main/postgresql.conf << 'EOF'

# Proxmox LXC optimizations
shared_buffers = 1024MB                # 25% of container RAM
effective_cache_size = 3GB             # 75% of container RAM
work_mem = 32MB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1                 # SSD optimization
effective_io_concurrency = 200         # SSD optimization

# Logging (adjust as needed)
log_line_prefix = '%t [%p-%l] %q%u@%d '
log_min_duration_statement = 1000      # Log slow queries
EOF

# Restart PostgreSQL
systemctl restart postgresql
```

### 19. Application Performance Tuning
```bash
# Create performance optimization script
cat > /usr/local/bin/optimize-flighttool.sh << 'EOF'
#!/bin/bash
# FlightTool performance optimization

# Set Node.js memory limit (adjust based on container RAM)
echo 'NODE_OPTIONS="--max-old-space-size=2048"' >> /home/flighttool/app/.env

# Optimize npm for production
npm config set production true
npm config set cache-max 86400

# Clear any existing cache
npm cache clean --force

# Restart application
systemctl restart flighttool

echo "FlightTool optimization completed"
EOF

chmod +x /usr/local/bin/optimize-flighttool.sh
```

## High Availability Setup (Optional)

### 20. Proxmox Cluster Configuration
For high availability across multiple Proxmox nodes:

```bash
# Create Proxmox cluster (run on first node)
pvecm create my-cluster

# Add additional nodes
pvecm add <first-node-ip>

# Configure shared storage for HA
# This requires additional setup depending on your storage backend
```

### 21. Container Migration
```bash
# Migrate container to another node (requires cluster)
pct migrate 100 <target-node>

# Clone container for testing
pct clone 100 101 --hostname flighttool-test --description "Test instance"
```

## Troubleshooting

### Common Proxmox Issues

**Container won't start:**
```bash
# Check container status
pct status 100

# View container configuration
pct config 100

# Check system logs
journalctl -u pve-container@100
```

**Network connectivity issues:**
```bash
# Check network configuration
pct exec 100 -- ip addr show
pct exec 100 -- ip route show

# Test connectivity
pct exec 100 -- ping 8.8.8.8
```

**Resource constraints:**
```bash
# Check resource usage
pct exec 100 -- htop
pveperf

# View container logs
pct exec 100 -- journalctl -f
```

**Application-specific issues:**
```bash
# Check application logs
pct exec 100 -- journalctl -u flighttool -n 50

# Check database connectivity
pct exec 100 -- sudo -u flighttool psql -h localhost -U flighttool -d flighttool -c "\l"

# Test application health
pct exec 100 -- curl -f http://localhost:3000/health
```

## Maintenance Tasks

### 22. Regular Maintenance Checklist

**Weekly:**
- Review application logs
- Check backup completion
- Monitor resource usage
- Update system packages

**Monthly:**
- Test backup restoration
- Review security logs
- Update application dependencies
- Optimize database (VACUUM, ANALYZE)

**Quarterly:**
- Security audit
- Performance review
- Capacity planning
- Disaster recovery testing

### 23. Update Procedures
```bash
# Update container system packages
pct exec 100 -- apt update && apt upgrade -y

# Update Node.js application
pct exec 100 -- su - flighttool -c "cd /home/flighttool/app && git pull && npm install && npm run build && npm run db:push"

# Restart application
pct exec 100 -- systemctl restart flighttool

# Update Proxmox VE (on host)
apt update && apt dist-upgrade
```

---

## Summary

This Proxmox VE deployment provides:

- ✅ **Enterprise-grade virtualization** with Proxmox VE management
- ✅ **LXC container isolation** with optimal performance
- ✅ **Comprehensive monitoring** through Proxmox interface
- ✅ **Automated backups** with flexible retention policies
- ✅ **High availability options** with clustering support
- ✅ **Resource management** with live adjustments
- ✅ **Security hardening** with firewall and SSL
- ✅ **Performance optimization** for container environment

Your FlightTool application is now running in a production-ready Proxmox VE environment with enterprise-level management, monitoring, and backup capabilities.