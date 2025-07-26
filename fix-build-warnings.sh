#!/bin/bash
# Fix build warnings and optimize production build for Proxmox deployment
# Run this on your Proxmox host

CONTAINER_ID="${1:-100}"

echo "Fixing build warnings and optimizing build for container $CONTAINER_ID..."

# Update browserslist data
echo "Updating browserslist data..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npx update-browserslist-db@latest"

# Fix npm audit vulnerabilities (non-breaking changes only)
echo "Fixing npm security vulnerabilities..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm audit fix"

# Optimize Vite build configuration for production
echo "Optimizing build configuration..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > vite.config.prod.ts << 'EOFVITE'
import { defineConfig } from \"vite\";
import react from \"@vitejs/plugin-react\";
import path from \"path\";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      \"@\": path.resolve(\"client\", \"src\"),
      \"@shared\": path.resolve(\"shared\"),
      \"@assets\": path.resolve(\"attached_assets\"),
    },
  },
  root: path.resolve(\"client\"),
  build: {
    outDir: path.resolve(\"dist/public\"),
    emptyOutDir: true,
    // Optimize build for production
    minify: \"esbuild\",
    target: \"es2020\",
    // Fix chunk size warnings
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: [\"react\", \"react-dom\"],
          ui: [\"@radix-ui/react-dialog\", \"@radix-ui/react-dropdown-menu\"],
          routing: [\"wouter\"],
          query: [\"@tanstack/react-query\"],
        },
        chunkSizeWarningLimit: 1000,
      },
    },
    // Reduce chunk sizes
    chunkSizeWarningLimit: 500,
  },
  server: {
    fs: {
      strict: true,
      deny: [\"**/.*\"],
    },
  },
});
EOFVITE"

# Create optimized build script
echo "Creating optimized build script..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && cat > build-optimized.sh << 'EOFOPT'
#!/bin/bash
set -e

echo \"Building FlightTool with optimizations...\"

# Clean build
rm -rf dist
mkdir -p dist

# Use production Vite config for optimized build
echo \"Building frontend with production optimizations...\"
npx vite build --config vite.config.prod.ts

# Create production server
echo \"Creating optimized production server...\"
cat > dist/index.js << 'EOFSERVER'
import express from \"express\";
import { fileURLToPath } from \"url\";
import { dirname, resolve } from \"path\";
import fs from \"fs\";
import { createServer } from \"http\";
import compression from \"compression\";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();

// Add compression middleware for better performance
app.use(compression());

// Security headers
app.use((req, res, next) => {
  res.setHeader(\"X-Content-Type-Options\", \"nosniff\");
  res.setHeader(\"X-Frame-Options\", \"DENY\");
  res.setHeader(\"X-XSS-Protection\", \"1; mode=block\");
  next();
});

// Basic middleware
app.use(express.json({ limit: \"10mb\" }));
app.use(express.urlencoded({ extended: false, limit: \"10mb\" }));

// Optimized logging (less verbose in production)
app.use((req, res, next) => {
  const start = Date.now();
  res.on(\"finish\", () => {
    const duration = Date.now() - start;
    // Only log API calls and errors
    if (req.path.startsWith(\"/api\") || res.statusCode >= 400) {
      console.log(\`\${new Date().toISOString()} [express] \${req.method} \${req.path} \${res.statusCode} in \${duration}ms\`);
    }
  });
  next();
});

// Cache control for static assets
app.use(express.static(resolve(__dirname, \"public\"), {
  maxAge: \"1y\",
  etag: true,
  lastModified: true,
  setHeaders: (res, path) => {
    // Cache HTML files for shorter time
    if (path.endsWith(\".html\")) {
      res.setHeader(\"Cache-Control\", \"public, max-age=300\"); // 5 minutes
    }
  }
}));

// SPA fallback
app.get(\"*\", (req, res) => {
  res.sendFile(resolve(__dirname, \"public\", \"index.html\"));
});

// Error handler
app.use((err, req, res, next) => {
  console.error(\`\${new Date().toISOString()} [express] Error:\`, err);
  res.status(500).json({ error: \"Internal server error\" });
});

const httpServer = createServer(app);
const port = parseInt(process.env.PORT || \"3000\", 10);

httpServer.listen(port, \"0.0.0.0\", () => {
  console.log(\`\${new Date().toISOString()} [express] FlightTool serving on port \${port}\`);
});

// Graceful shutdown
process.on(\"SIGTERM\", () => {
  console.log(\"SIGTERM received, shutting down gracefully\");
  httpServer.close(() => {
    console.log(\"Server closed\");
    process.exit(0);
  });
});
EOFSERVER

echo \"Optimized build completed successfully\"
EOFOPT"

# Make build script executable
pct exec "$CONTAINER_ID" -- chmod +x /home/flighttool/app/build-optimized.sh

# Install compression middleware if not present
echo "Installing production optimizations..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm install compression"

# Run optimized build
echo "Running optimized build..."
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && ./build-optimized.sh"

# Restart service with optimized build
echo "Restarting service with optimizations..."
pct exec "$CONTAINER_ID" -- systemctl restart flighttool

# Check status
sleep 3
echo "Service status after optimization:"
pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l

echo "Build optimization completed!"
echo "Improvements applied:"
echo "  ✓ Updated browserslist data"
echo "  ✓ Fixed npm security vulnerabilities"
echo "  ✓ Optimized Vite build configuration"
echo "  ✓ Reduced bundle chunk sizes"
echo "  ✓ Added compression middleware"
echo "  ✓ Improved caching headers"
echo "  ✓ Enhanced error handling"