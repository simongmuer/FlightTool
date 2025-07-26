# Let's Encrypt SSL Certificate Setup for FlightTool

This guide explains how to enable HTTPS with automatic SSL certificate management for your FlightTool deployment.

## Quick Setup

The simplest way to enable SSL is using the automated script:

```bash
sudo ./enable-ssl.sh your-domain.com
```

Replace `your-domain.com` with your actual domain name.

## Prerequisites

Before running the SSL setup:

1. **Domain Configuration**: Your domain must point to your server's IP address
2. **Ports Open**: Ensure ports 80 and 443 are open in your firewall
3. **Root Access**: You need sudo/root privileges
4. **FlightTool Running**: Your FlightTool application should be running on port 5000

## Manual Setup Steps

If you prefer manual setup or need to troubleshoot:

### 1. Install Certbot

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx
```

**CentOS/RHEL:**
```bash
sudo yum install epel-release
sudo yum install certbot python3-certbot-nginx
```

**Fedora:**
```bash
sudo dnf install certbot python3-certbot-nginx
```

### 2. Configure Nginx

Create or update your nginx configuration:

```bash
sudo nano /etc/nginx/sites-available/flighttool
```

Add the following configuration:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }
    
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    # SSL certificates (will be configured by certbot)
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
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
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Static files with caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://localhost:5000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
}
```

### 3. Enable the Site

```bash
sudo ln -s /etc/nginx/sites-available/flighttool /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### 4. Generate SSL Certificate

```bash
sudo certbot --nginx -d your-domain.com
```

Follow the prompts to:
- Agree to terms of service
- Provide email (optional)
- Choose redirect option (recommended)

### 5. Test SSL Configuration

```bash
curl -I https://your-domain.com
```

You should see a successful HTTPS response.

## Automatic Renewal

Certbot automatically sets up renewal. You can test it with:

```bash
sudo certbot renew --dry-run
```

Check the renewal timer:

```bash
sudo systemctl status certbot.timer
```

## Custom Renewal Script

The automated script creates a custom renewal script that also handles FlightTool service restarts:

```bash
# Location: /usr/local/bin/flighttool-ssl-renew
# Scheduled via cron: 0 */12 * * *
```

## Troubleshooting

### Certificate Generation Fails

1. **DNS Issue**: Verify your domain points to the server
   ```bash
   dig +short your-domain.com
   curl ifconfig.me
   ```

2. **Port 80 Blocked**: Ensure port 80 is accessible
   ```bash
   sudo ufw allow 80
   sudo ufw allow 443
   ```

3. **Nginx Not Running**: Make sure nginx is active
   ```bash
   sudo systemctl start nginx
   sudo systemctl enable nginx
   ```

### Certificate Already Exists

If you get a "certificate already exists" error:

```bash
sudo certbot certificates
sudo certbot renew --force-renewal -d your-domain.com
```

### Renewal Fails

Check the renewal logs:

```bash
sudo cat /var/log/letsencrypt/letsencrypt.log
sudo cat /var/log/flighttool-ssl-renewal.log
```

## Security Enhancements

The configuration includes several security features:

- **HSTS Headers**: Force HTTPS connections
- **XSS Protection**: Prevent cross-site scripting
- **Frame Options**: Prevent clickjacking
- **Content Type Options**: Prevent MIME sniffing
- **Secure Proxy Headers**: Proper forwarding for HTTPS

## Firewall Configuration

If using UFW firewall:

```bash
sudo ufw allow 'Nginx Full'
sudo ufw delete allow 'Nginx HTTP'
```

For iptables:

```bash
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

## Certificate Information

View certificate details:

```bash
sudo certbot certificates
```

Check expiration:

```bash
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

## Multiple Domains

To add multiple domains to the same certificate:

```bash
sudo certbot --nginx -d domain1.com -d www.domain1.com -d domain2.com
```

## Wildcard Certificates

For wildcard certificates (requires DNS validation):

```bash
sudo certbot certonly --manual --preferred-challenges dns -d *.your-domain.com -d your-domain.com
```

## Support

If you encounter issues:

1. Check the Let's Encrypt community forum
2. Verify your domain configuration
3. Ensure all prerequisites are met
4. Review nginx and certbot logs

The automated script handles most common scenarios and provides detailed error messages for troubleshooting.