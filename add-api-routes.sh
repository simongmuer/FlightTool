#!/bin/bash
# Add API routes to the running FlightTool service
# Run this on your Proxmox host

CONTAINER_ID="${1:-100}"

echo "Adding API routes to FlightTool in container $CONTAINER_ID..."

# Stop the service temporarily
pct exec "$CONTAINER_ID" -- systemctl stop flighttool

# Create a server with proper API routes
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > dist/index.js << 'EOFSERVER'
import express from \"express\";
import { fileURLToPath } from \"url\";
import { dirname, resolve } from \"path\";
import fs from \"fs\";
import { createServer } from \"http\";
import session from \"express-session\";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();

// Basic middleware
app.use(express.json({ limit: \"10mb\" }));
app.use(express.urlencoded({ extended: false, limit: \"10mb\" }));

// Session middleware (simplified for now)
app.use(session({
  secret: process.env.SESSION_SECRET || \"dev-secret-change-in-production\",
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: false, // Set to true in production with HTTPS
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000 // 24 hours
  }
}));

// Logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on(\"finish\", () => {
    const duration = Date.now() - start;
    if (req.path.startsWith(\"/api\")) {
      console.log(\`\${new Date().toISOString()} [express] \${req.method} \${req.path} \${res.statusCode} in \${duration}ms\`);
    }
  });
  next();
});

// Basic API routes
app.get(\"/api/auth/user\", (req, res) => {
  // For now, return unauthorized - will implement proper auth later
  res.status(401).json({ message: \"Unauthorized\" });
});

app.get(\"/api/login\", (req, res) => {
  // Placeholder login route
  res.json({ 
    message: \"Login endpoint available\", 
    note: \"Full authentication system will be implemented in next phase\",
    redirect: \"/\"
  });
});

app.get(\"/api/logout\", (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      console.error(\"Session destruction error:\", err);
    }
    res.redirect(\"/\");
  });
});

// Health check endpoint
app.get(\"/api/health\", (req, res) => {
  res.json({ 
    status: \"healthy\", 
    timestamp: new Date().toISOString(),
    version: \"1.0.0\",
    environment: process.env.NODE_ENV || \"development\"
  });
});

// Static file serving
const distPath = resolve(__dirname, \"public\");
if (fs.existsSync(distPath)) {
  app.use(express.static(distPath, {
    maxAge: \"1h\",
    etag: true
  }));
} else {
  console.warn(\"Frontend build directory not found:\", distPath);
}

// SPA fallback for all non-API routes
app.get(\"*\", (req, res) => {
  const indexPath = resolve(distPath, \"index.html\");
  if (fs.existsSync(indexPath)) {
    res.sendFile(indexPath);
  } else {
    res.status(503).send(\"Application not properly built. Frontend assets missing.\");
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(\`\${new Date().toISOString()} [express] Error:\`, err);
  res.status(500).json({ 
    error: \"Internal server error\",
    message: process.env.NODE_ENV === \"development\" ? err.message : \"Something went wrong\"
  });
});

// Create HTTP server
const httpServer = createServer(app);
const port = parseInt(process.env.PORT || \"3000\", 10);

httpServer.listen(port, \"0.0.0.0\", () => {
  console.log(\`\${new Date().toISOString()} [express] FlightTool with API routes serving on port \${port}\`);
  console.log(\`Available endpoints:\`);
  console.log(\`  GET  /api/health - Health check\`);
  console.log(\`  GET  /api/login - Login endpoint\`);
  console.log(\`  GET  /api/logout - Logout endpoint\`);
  console.log(\`  GET  /api/auth/user - User info (requires auth)\`);
  console.log(\`  GET  /* - Frontend application\`);
});

// Graceful shutdown
process.on(\"SIGTERM\", () => {
  console.log(\"SIGTERM received, shutting down gracefully\");
  httpServer.close(() => {
    console.log(\"Server closed\");
    process.exit(0);
  });
});

process.on(\"SIGINT\", () => {
  console.log(\"SIGINT received, shutting down gracefully\");
  httpServer.close(() => {
    console.log(\"Server closed\");
    process.exit(0);
  });
});
EOFSERVER"

# Install express-session if not already installed
echo "Installing required session middleware..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm install express-session"

# Fix permissions
pct exec "$CONTAINER_ID" -- chown -R flighttool:flighttool /home/flighttool/app
pct exec "$CONTAINER_ID" -- chmod 755 /home/flighttool/app/dist/index.js

# Start the service
echo "Starting FlightTool with API routes..."
pct exec "$CONTAINER_ID" -- systemctl start flighttool

# Wait for startup and check status
sleep 3
echo "Service status:"
pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l

echo ""
echo "API routes added successfully!"
echo "Available endpoints:"
echo "  GET  /api/health - Health check"
echo "  GET  /api/login - Login endpoint"  
echo "  GET  /api/logout - Logout endpoint"
echo "  GET  /api/auth/user - User info"
echo ""
echo "Test the endpoints:"
echo "  curl http://your-server:3000/api/health"
echo "  curl http://your-server:3000/api/login"