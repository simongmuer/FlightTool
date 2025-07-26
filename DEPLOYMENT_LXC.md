# FlightTool LXC Container Deployment Guide

This guide explains how to deploy your FlightTool application in a single LXC container with all dependencies included. This provides excellent isolation, resource control, and security for production deployments.

## Overview

LXC (Linux Containers) offers operating-system-level virtualization that's more efficient than VMs while providing excellent isolation. This deployment method creates a complete, self-contained environment for FlightTool.

## Prerequisites

### Host System Requirements
- **Ubuntu 20.04+ or Debian 11+** (or compatible Linux distribution)
- **LXD/LXC installed and configured**
- **4GB RAM minimum** (8GB recommended for production)
- **20GB storage minimum** for the container
- **Root or sudo access** on the host system

### Install LXD/LXC
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install lxd lxc-utils

# Initialize LXD (run as user who will manage containers)
sudo lxd init
# Accept defaults or configure as needed

# Add your user to lxd group
sudo usermod -a -G lxd $USER
newgrp lxd
```

## Container Setup

### 1. Create the LXC Container
```bash
# Create container with Ubuntu 22.04
lxc launch ubuntu:22.04 flighttool-app

# Wait for container to start
lxc list

# Enter the container
lxc shell flighttool-app
```

### 2. Install Dependencies in Container
```bash
# Update system
apt update && apt upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Install additional tools
apt-get install -y git curl wget nginx certbot

# Verify installations
node --version
npm --version
psql --version
```

### 3. Configure PostgreSQL
```bash
# Start PostgreSQL service
systemctl start postgresql
systemctl enable postgresql

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE flighttool;
CREATE USER flighttool WITH PASSWORD 'secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
ALTER USER flighttool CREATEDB;
\q
EOF

# Configure PostgreSQL for local connections
echo "local   all             flighttool                              md5" >> /etc/postgresql/*/main/pg_hba.conf
systemctl restart postgresql
```

## Application Deployment

### 4. Deploy FlightTool Application
```bash
# Create application directory
mkdir -p /opt/flighttool
cd /opt/flighttool

# Clone your repository (replace with your actual repo)
git clone https://github.com/yourusername/flighttool.git .

# Install all dependencies (including dev dependencies for build)
npm install

# Create environment file
cat > .env << EOF
NODE_ENV=production
DATABASE_URL=postgresql://flighttool:secure_password_here@localhost:5432/flighttool
SESSION_SECRET=$(openssl rand -base64 32)
PORT=3000
REPLIT_DOMAINS=yourdomain.com
EOF

# Build application
npm run build

# Run database migrations (before removing dev dependencies)
npm run db:push

# Remove dev dependencies after build and migrations
npm prune --production

# Create application user
useradd -r -s /bin/false flighttool
chown -R flighttool:flighttool /opt/flighttool
```

### 5. Create Systemd Service
```bash
cat > /etc/systemd/system/flighttool.service << EOF
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
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable flighttool
systemctl start flighttool

# Check status
systemctl status flighttool
```

### 6. Configure Nginx Reverse Proxy
```bash
cat > /etc/nginx/sites-available/flighttool << EOF
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL configuration (update paths as needed)
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Proxy to Node.js application
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

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/flighttool /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload nginx
nginx -t
systemctl enable nginx
systemctl restart nginx
```

## Container Network Configuration

### 7. Configure Container Networking
```bash
# Exit container shell
exit

# Configure port forwarding on host
lxc config device add flighttool-app http proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80
lxc config device add flighttool-app https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443

# Alternatively, use bridge networking for direct access
lxc config device add flighttool-app eth0 nic nictype=bridged parent=lxdbr0
```

## SSL Certificate Setup

### 8. Configure Let's Encrypt SSL
```bash
# Enter container
lxc shell flighttool-app

# Obtain SSL certificate
certbot --nginx -d yourdomain.com -d www.yourdomain.com

# Set up auto-renewal
echo "0 2 * * * root certbot renew --quiet" >> /etc/crontab
```

## Management and Monitoring

### 9. Container Management Commands
```bash
# Start/stop container
lxc start flighttool-app
lxc stop flighttool-app

# Restart services inside container
lxc exec flighttool-app -- systemctl restart flighttool
lxc exec flighttool-app -- systemctl restart nginx

# View logs
lxc exec flighttool-app -- journalctl -u flighttool -f
lxc exec flighttool-app -- tail -f /var/log/nginx/access.log

# Monitor resource usage
lxc info flighttool-app

# Backup container
lxc snapshot flighttool-app backup-$(date +%Y%m%d)
lxc export flighttool-app flighttool-backup.tar.gz
```

### 10. Set Resource Limits
```bash
# Limit CPU and memory usage
lxc config set flighttool-app limits.cpu 2
lxc config set flighttool-app limits.memory 4GB

# Limit disk usage
lxc config device override flighttool-app root size=20GB

# Set I/O limits
lxc config set flighttool-app limits.disk.priority 5
```

## Security Hardening

### 11. Container Security
```bash
# Disable unnecessary services in container
lxc exec flighttool-app -- systemctl disable snapd
lxc exec flighttool-app -- systemctl disable bluetooth

# Configure firewall (if needed)
lxc exec flighttool-app -- ufw enable
lxc exec flighttool-app -- ufw allow 22,80,443/tcp

# Set up automatic security updates
lxc exec flighttool-app -- apt install unattended-upgrades
```

## Backup and Recovery

### 12. Backup Strategy
```bash
#!/bin/bash
# backup-flighttool.sh - Daily backup script

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/flighttool"

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup database
lxc exec flighttool-app -- sudo -u postgres pg_dump flighttool > $BACKUP_DIR/db_$DATE.sql

# Backup container snapshot
lxc snapshot flighttool-app daily-$DATE

# Export container (full backup)
lxc export flighttool-app $BACKUP_DIR/container_$DATE.tar.gz

# Clean old backups (keep 7 days)
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
lxc delete flighttool-app/daily-$(date -d "7 days ago" +%Y%m%d_%H%M%S) 2>/dev/null || true

echo "Backup completed: $DATE"
```

### 13. Setup Automated Backups
```bash
# Make backup script executable
chmod +x backup-flighttool.sh

# Add to crontab for daily backups at 2 AM
echo "0 2 * * * /root/backup-flighttool.sh" >> /etc/crontab
```

## Troubleshooting

### Common Issues

**Container won't start:**
```bash
lxc info flighttool-app --show-log
lxc config show flighttool-app
```

**Application errors:**
```bash
lxc exec flighttool-app -- journalctl -u flighttool -n 50
lxc exec flighttool-app -- npm run check
```

**Database connection issues:**
```bash
lxc exec flighttool-app -- sudo -u postgres psql -c "\l"
lxc exec flighttool-app -- systemctl status postgresql
```

**Network problems:**
```bash
lxc list
lxc network show lxdbr0
```

## Performance Optimization

### 14. Production Optimization
```bash
# Enable container optimization
lxc config set flighttool-app security.nesting true
lxc config set flighttool-app security.privileged false

# Optimize PostgreSQL for container
lxc exec flighttool-app -- bash << 'EOF'
cat >> /etc/postgresql/*/main/postgresql.conf << PGCONF
# Container optimizations
shared_buffers = 512MB
effective_cache_size = 2GB
work_mem = 16MB
maintenance_work_mem = 128MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
PGCONF
systemctl restart postgresql
EOF
```

## Container Templates

### 15. Create Reusable Template
```bash
# Stop container
lxc stop flighttool-app

# Create image template
lxc publish flighttool-app --alias flighttool-template

# Launch new instances from template
lxc launch flighttool-template new-flighttool-instance
```

---

## Summary

This LXC deployment provides:
- ✅ **Complete isolation** with OS-level virtualization
- ✅ **Resource control** with CPU, memory, and disk limits
- ✅ **Security hardening** with proper user permissions and firewall
- ✅ **Production-ready** with SSL, reverse proxy, and monitoring
- ✅ **Automated backups** and recovery procedures
- ✅ **Scalability** through container templates and snapshots

Your FlightTool application is now running in a secure, isolated LXC container with all dependencies contained and properly configured for production use.