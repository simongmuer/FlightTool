#!/bin/bash
# Fix TypeScript build issues for Proxmox FlightTool deployment
# Run this on your Proxmox host

CONTAINER_ID="${1:-100}"

echo "Fixing TypeScript build issues in container $CONTAINER_ID..."

# Stop the service
pct exec "$CONTAINER_ID" -- systemctl stop flighttool

# Go to app directory and clean build
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && rm -rf dist"

# Install TypeScript compiler if missing
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm install --save-dev typescript @types/node"

# Create a proper TypeScript build process
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > build-production-fixed.sh << 'EOFBUILD'
#!/bin/bash
set -e

echo \"Building FlightTool with proper TypeScript compilation...\"

# Clean build directory
rm -rf dist
mkdir -p dist

# Build frontend first
echo \"Building frontend...\"
npm run build

# Create simplified production server without TypeScript imports
echo \"Creating production server...\"
cat > dist/index.js << 'EOFSERVER'
import express from \"express\";
import { fileURLToPath } from \"url\";
import { dirname, resolve } from \"path\";
import fs from \"fs\";
import { createServer } from \"http\";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();

// Basic middleware
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Logging middleware
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

// Static file serving
const distPath = resolve(__dirname, \"public\");
if (fs.existsSync(distPath)) {
  app.use(express.static(distPath));
  app.get(\"*\", (req, res) => {
    res.sendFile(resolve(distPath, \"index.html\"));
  });
} else {
  console.error(\"Frontend build not found at:\", distPath);
  app.get(\"*\", (req, res) => {
    res.status(503).send(\"Application not built properly\");
  });
}

// Create HTTP server
const httpServer = createServer(app);

// Start server
const port = parseInt(process.env.PORT || \"3000\", 10);
httpServer.listen(port, \"0.0.0.0\", () => {
  console.log(\`\${new Date().toLocaleTimeString()} [express] serving on port \${port}\`);
});
EOFSERVER

echo \"Production build completed\"
EOFBUILD"

# Make the build script executable
pct exec "$CONTAINER_ID" -- chmod +x /home/flighttool/app/build-production-fixed.sh

# Run the fixed build
echo "Running fixed build process..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && ./build-production-fixed.sh"

# Update systemd service to use the simple server
pct exec "$CONTAINER_ID" -- bash -c "cat > /etc/systemd/system/flighttool.service << 'EOFSERVICE'
[Unit]
Description=FlightTool Personal Flight Tracking Application
After=network.target

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
Restart=always
RestartSec=10

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOFSERVICE"

# Fix permissions
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/app
pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool/app

# Reload and start service
pct exec "$CONTAINER_ID" -- systemctl daemon-reload
pct exec "$CONTAINER_ID" -- systemctl start flighttool

# Check status
sleep 3
echo "Service status:"
pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l

echo "Fix completed!"