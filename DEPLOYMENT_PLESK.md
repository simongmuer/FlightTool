# FlightTool Deployment Guide for Plesk

This guide explains how to deploy your FlightTool application to a web server running Plesk control panel.

## Prerequisites

Before deployment, ensure your Plesk hosting includes:
- **Node.js support** (version 18 or higher)
- **PostgreSQL database** access
- **SSH access** (recommended) or File Manager
- **Domain/subdomain** configured in Plesk

## Step 1: Prepare Your Hosting Environment

### 1.1 Create a Database in Plesk
1. Log into your Plesk control panel
2. Go to **Databases** → **Add Database**
3. Create a new PostgreSQL database:
   - Database name: `flighttool_db`
   - User: `flighttool_user`
   - Password: (generate a strong password)
4. Note down the connection details for later

### 1.2 Enable Node.js
1. In Plesk, go to **Node.js**
2. Enable Node.js for your domain
3. Set Node.js version to **18.x** or higher
4. Set the application startup file to: `server/index.js`

## Step 2: Upload and Configure Files

### 2.1 Upload Source Files
Upload all project files to your domain's directory (typically `httpdocs/` or `public_html/`):

```
httpdocs/
├── client/
├── server/
├── shared/
├── package.json
├── package-lock.json
├── drizzle.config.ts
├── vite.config.ts
├── tsconfig.json
├── tailwind.config.ts
├── postcss.config.js
├── components.json
└── .env (create this file)
```

### 2.2 Create Environment File
Create a `.env` file in the root directory with your production settings:

```env
# Database Configuration
DATABASE_URL=postgresql://flighttool_user:YOUR_PASSWORD@localhost:5432/flighttool_db

# Session Configuration
SESSION_SECRET=your-super-secure-session-secret-here

# Replit Auth (if using Replit Auth)
REPLIT_DOMAINS=yourdomain.com
REPL_ID=your-repl-id
ISSUER_URL=https://replit.com/oidc

# Production Settings
NODE_ENV=production
PORT=3000
```

## Step 3: Install Dependencies and Build

### 3.1 Via SSH (Recommended)
If you have SSH access:

```bash
# Navigate to your domain directory
cd /var/www/vhosts/yourdomain.com/httpdocs

# Install dependencies
npm install

# Build the frontend
npm run build

# Run database migrations
npm run db:push
```

### 3.2 Via Plesk Node.js Interface
1. Go to **Node.js** in Plesk
2. Click **NPM Install** to install dependencies
3. Use the **Run Script** feature to execute:
   - `npm run build`
   - `npm run db:push`

## Step 4: Configure Application Startup

### 4.1 Update package.json Scripts
Ensure your `package.json` has the correct production scripts:

```json
{
  "scripts": {
    "dev": "NODE_ENV=development tsx server/index.ts",
    "build": "vite build",
    "start": "NODE_ENV=production node server/index.js",
    "db:push": "drizzle-kit push",
    "db:studio": "drizzle-kit studio"
  }
}
```

### 4.2 Compile TypeScript for Production
Since Plesk may not support TypeScript directly, compile your server code:

```bash
# Install TypeScript compiler globally (if not available)
npm install -g typescript tsx

# Compile server TypeScript to JavaScript
npx tsc server/index.ts --outDir server --target es2022 --module commonjs
```

## Step 5: Configure Plesk Application Settings

### 5.1 Node.js Application Settings
In Plesk Node.js section:
- **Application mode**: Production
- **Application startup file**: `server/index.js`
- **Application URL**: Leave as is or set custom path
- **Environment variables**: Add any additional vars if needed

### 5.2 Restart Application
Click **Restart** in the Node.js section to start your application.

## Step 6: Database Setup

### 6.1 Run Migrations
Execute the database migration to create tables:

```bash
npm run db:push
```

### 6.2 Verify Database Tables
Check that these tables were created:
- `users`
- `flights`
- `airlines`
- `airports`
- `sessions`

## Step 7: Configure Web Server (Optional)

### 7.1 Nginx/Apache Proxy (if needed)
If your Node.js app runs on a different port, configure a proxy in Plesk:

For Apache (`.htaccess` in httpdocs):
```apache
RewriteEngine On
RewriteRule ^api/(.*)$ http://localhost:3000/api/$1 [P,L]
RewriteRule ^(?!api).*$ /index.html [L]
```

For Nginx:
```nginx
location /api/ {
    proxy_pass http://localhost:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}

location / {
    try_files $uri $uri/ /index.html;
}
```

## Step 8: SSL Certificate

### 8.1 Enable HTTPS
1. In Plesk, go to **SSL/TLS Certificates**
2. Install a Let's Encrypt certificate or upload your own
3. Enable **Force HTTPS redirect**

### 8.2 Update Environment for HTTPS
Ensure your `.env` uses HTTPS URLs:
```env
REPLIT_DOMAINS=https://yourdomain.com
```

## Step 9: Testing and Verification

### 9.1 Test Application
1. Visit your domain to see the landing page
2. Try logging in (if using Replit Auth, configure OAuth redirect URLs)
3. Test flight creation and CSV import functionality
4. Check that all static assets load correctly

### 9.2 Monitor Logs
Check application logs in Plesk:
- Node.js logs for runtime errors
- Error logs for any server issues

## Troubleshooting Common Issues

### Issue: "Module not found" errors
**Solution**: Ensure all dependencies are installed and paths are correct

### Issue: Database connection failed
**Solution**: Verify DATABASE_URL format and credentials

### Issue: Static files not loading
**Solution**: Ensure build process completed and files are in correct location

### Issue: Authentication not working
**Solution**: Check OAuth redirect URLs and environment variables

## Alternative: Docker Deployment (Advanced)

If your Plesk supports Docker, you can containerize the application:

1. Create a `Dockerfile`:
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
```

2. Build and deploy via Plesk Docker interface

## Performance Optimization

### Production Optimizations
1. **Enable compression** in Plesk web server settings
2. **Set up caching** for static assets
3. **Configure CDN** for better global performance
4. **Monitor resource usage** and scale as needed

### Database Optimization
1. **Create indexes** on frequently queried columns
2. **Set up database backups** in Plesk
3. **Monitor database performance** and optimize queries

---

Your FlightTool application should now be successfully deployed on your Plesk web server. The application will be accessible via your domain and ready for production use.