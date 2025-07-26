#!/bin/bash

# FlightTool Let's Encrypt SSL Certificate Setup Script
# This script enables HTTPS with automatic SSL certificate management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get domain name
if [ -z "$1" ]; then
    read -p "Enter your domain name (e.g., flighttool.example.com): " DOMAIN
else
    DOMAIN="$1"
fi

if [ -z "$DOMAIN" ]; then
    print_error "Domain name is required"
    exit 1
fi

# Validate domain format
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    print_error "Invalid domain name format"
    exit 1
fi

print_status "Setting up SSL certificate for domain: $DOMAIN"

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION=$VERSION_ID
else
    print_error "Cannot detect operating system"
    exit 1
fi

print_status "Detected OS: $OS $VERSION"

# Install Certbot based on OS
install_certbot() {
    case "$OS" in
        "Ubuntu"*|"Debian"*)
            print_status "Installing certbot for Ubuntu/Debian..."
            apt update
            apt install -y certbot python3-certbot-nginx
            ;;
        "CentOS"*|"Red Hat"*)
            print_status "Installing certbot for CentOS/RHEL..."
            yum install -y epel-release
            yum install -y certbot python3-certbot-nginx
            ;;
        "Fedora"*)
            print_status "Installing certbot for Fedora..."
            dnf install -y certbot python3-certbot-nginx
            ;;
        "Arch Linux"*)
            print_status "Installing certbot for Arch Linux..."
            pacman -S --noconfirm certbot certbot-nginx
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
}

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    print_warning "Certbot not found. Installing..."
    install_certbot
else
    print_success "Certbot is already installed"
fi

# Check if nginx is installed and running
if ! command -v nginx &> /dev/null; then
    print_error "Nginx is not installed. Please install nginx first."
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    print_warning "Nginx is not running. Starting nginx..."
    systemctl start nginx
    systemctl enable nginx
fi

# Backup existing nginx configuration
NGINX_CONF="/etc/nginx/sites-available/flighttool"
NGINX_ENABLED="/etc/nginx/sites-enabled/flighttool"

if [ -f "$NGINX_CONF" ]; then
    print_status "Backing up existing nginx configuration..."
    cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create nginx configuration for domain validation
print_status "Creating nginx configuration for SSL certificate validation..."

cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Allow Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }
    
    # Redirect all other traffic to HTTPS (will be enabled after cert generation)
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS configuration (will be populated by certbot)
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL configuration will be added by certbot
    
    # Proxy to FlightTool application
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # WebSocket support
        proxy_set_header Sec-WebSocket-Extensions \$http_sec_websocket_extensions;
        proxy_set_header Sec-WebSocket-Key \$http_sec_websocket_key;
        proxy_set_header Sec-WebSocket-Version \$http_sec_websocket_version;
        
        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    }
    
    # API routes
    location /api/ {
        proxy_pass http://localhost:5000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://localhost:5000;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
}
EOF

# Enable the site
if [ ! -L "$NGINX_ENABLED" ]; then
    ln -s "$NGINX_CONF" "$NGINX_ENABLED"
fi

# Remove default nginx site if it exists
if [ -L "/etc/nginx/sites-enabled/default" ]; then
    rm "/etc/nginx/sites-enabled/default"
fi

# Test nginx configuration
print_status "Testing nginx configuration..."
if nginx -t; then
    print_success "Nginx configuration is valid"
    systemctl reload nginx
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# Create web root for Let's Encrypt validation
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html 2>/dev/null || chown -R nginx:nginx /var/www/html 2>/dev/null || true

# Check if domain points to this server
print_status "Checking DNS resolution for $DOMAIN..."
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)

if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
    print_warning "Domain $DOMAIN resolves to $DOMAIN_IP but this server's IP is $SERVER_IP"
    print_warning "Make sure your domain's DNS A record points to this server's IP address"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Generate SSL certificate
print_status "Generating SSL certificate with Let's Encrypt..."

# Check if certificate already exists
if certbot certificates 2>/dev/null | grep -q "$DOMAIN"; then
    print_warning "Certificate for $DOMAIN already exists"
    read -p "Renew existing certificate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        certbot renew --nginx --non-interactive
    fi
else
    # Request new certificate
    if certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN"; then
        print_success "SSL certificate generated successfully!"
    else
        print_error "Failed to generate SSL certificate"
        print_error "Please check:"
        print_error "1. Domain $DOMAIN points to this server"
        print_error "2. Port 80 and 443 are open in firewall"
        print_error "3. No other service is using port 80"
        exit 1
    fi
fi

# Setup automatic renewal
print_status "Setting up automatic certificate renewal..."

# Create renewal script
cat > /usr/local/bin/flighttool-ssl-renew << 'EOF'
#!/bin/bash
# FlightTool SSL Certificate Renewal Script

log_file="/var/log/flighttool-ssl-renewal.log"

echo "$(date): Starting SSL certificate renewal check" >> "$log_file"

if certbot renew --nginx --quiet >> "$log_file" 2>&1; then
    echo "$(date): Certificate renewal check completed successfully" >> "$log_file"
    
    # Restart FlightTool service if needed
    if systemctl is-active --quiet flighttool; then
        systemctl reload nginx
        echo "$(date): Nginx reloaded after certificate renewal" >> "$log_file"
    fi
else
    echo "$(date): Certificate renewal failed" >> "$log_file"
fi
EOF

chmod +x /usr/local/bin/flighttool-ssl-renew

# Add to crontab for automatic renewal (check twice daily)
if ! crontab -l 2>/dev/null | grep -q "flighttool-ssl-renew"; then
    (crontab -l 2>/dev/null; echo "0 */12 * * * /usr/local/bin/flighttool-ssl-renew") | crontab -
    print_success "Automatic renewal scheduled (twice daily)"
fi

# Update FlightTool environment for HTTPS
FLIGHTTOOL_ENV="/home/flighttool/.env"
if [ -f "$FLIGHTTOOL_ENV" ]; then
    print_status "Updating FlightTool environment for HTTPS..."
    
    # Update or add HTTPS settings
    if grep -q "HTTPS_ENABLED" "$FLIGHTTOOL_ENV"; then
        sed -i 's/HTTPS_ENABLED=.*/HTTPS_ENABLED=true/' "$FLIGHTTOOL_ENV"
    else
        echo "HTTPS_ENABLED=true" >> "$FLIGHTTOOL_ENV"
    fi
    
    if grep -q "DOMAIN" "$FLIGHTTOOL_ENV"; then
        sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN/" "$FLIGHTTOOL_ENV"
    else
        echo "DOMAIN=$DOMAIN" >> "$FLIGHTTOOL_ENV"
    fi
    
    # Restart FlightTool service
    if systemctl is-active --quiet flighttool; then
        print_status "Restarting FlightTool service..."
        systemctl restart flighttool
    fi
fi

# Open firewall ports if ufw is active
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    print_status "Opening firewall ports for HTTPS..."
    ufw allow 443/tcp
    ufw reload
fi

# Final status check
print_status "Performing final SSL verification..."
sleep 5

if curl -s -I "https://$DOMAIN" | grep -q "HTTP/2 200"; then
    print_success "✅ SSL certificate is working correctly!"
    print_success "✅ FlightTool is now accessible at: https://$DOMAIN"
    print_success "✅ Automatic renewal is configured"
    
    echo
    print_status "SSL Certificate Information:"
    certbot certificates | grep -A 10 "$DOMAIN"
    
    echo
    print_status "Next steps:"
    echo "1. Update your DNS if needed to point to this server"
    echo "2. Update any bookmarks to use https://$DOMAIN"
    echo "3. Consider setting up a redirect from www.$DOMAIN if needed"
    echo "4. Certificate will auto-renew every 60 days"
else
    print_warning "SSL certificate was installed but verification failed"
    print_warning "Please check manually at: https://$DOMAIN"
fi

print_success "SSL setup completed!"