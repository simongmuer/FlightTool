#!/bin/bash
# Immediate fix for current Proxmox FlightTool deployment
# Run this on your Proxmox host

CONTAINER_ID="${1:-100}"

echo "Applying immediate fix to container $CONTAINER_ID..."

# Stop the failing service
pct exec "$CONTAINER_ID" -- systemctl stop flighttool

# Create a working production server
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > dist/index.js << 'EOF'
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
      console.error(\`Build directory not found: \${distPath}\`);
      process.exit(1);
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
EOF"

# Rebuild server modules without Vite dependencies
echo "Rebuilding server modules..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npx esbuild server/routes.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/routes.js --external:express --external:openid-client --external:passport* --external:drizzle-orm --external:postgres --external:connect-pg-simple --external:express-session --external:memoizee --external:multer --external:csv-parser"
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npx esbuild server/storage.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/storage.js --external:drizzle-orm --external:postgres"
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npx esbuild server/db.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/db.js --external:drizzle-orm --external:postgres --external:@neondatabase/serverless"
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npx esbuild server/replitAuth.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/replitAuth.js --external:openid-client --external:passport* --external:express-session --external:connect-pg-simple --external:memoizee"

# Copy shared schema
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && mkdir -p dist/shared && cp shared/schema.ts dist/shared/"

# Fix permissions
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/app
pct exec "$CONTAINER_ID" -- chmod -R 755 /home/flighttool/app

# Start the service
echo "Starting FlightTool service..."
pct exec "$CONTAINER_ID" -- systemctl start flighttool

# Check status
sleep 3
pct exec "$CONTAINER_ID" -- systemctl status flighttool

echo "Fix applied! Check the service status above."