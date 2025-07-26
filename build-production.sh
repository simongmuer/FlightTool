#!/bin/bash
# Production build script for FlightTool
# This script properly builds the application for production deployment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "Starting FlightTool production build..."

# Clean any existing build
if [ -d "dist" ]; then
    log_info "Cleaning existing build directory..."
    rm -rf dist
fi

# Install all dependencies (including dev dependencies for build)
log_info "Installing dependencies..."
npm install

# Build frontend with Vite
log_info "Building frontend..."
npm run build 2>&1 | grep -v "Browserslist:"

# Verify frontend build
if [ ! -d "dist/public" ]; then
    log_error "Frontend build failed - dist/public not found"
    exit 1
fi

log_info "✓ Frontend build completed"

# Create a production-ready server bundle
log_info "Building server..."

# Create the dist directory for server if it doesn't exist
mkdir -p dist

# Create a simplified production server that doesn't import Vite
cat > dist/index.js << 'EOF'
import express from "express";
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();

// Basic middleware
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Simple logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    const duration = Date.now() - start;
    if (req.path.startsWith("/api")) {
      console.log(`${new Date().toLocaleTimeString()} [express] ${req.method} ${req.path} ${res.statusCode} in ${duration}ms`);
    }
  });
  next();
});

// Import and register routes
import('./routes.js').then(({ registerRoutes }) => {
  registerRoutes(app).then((server) => {
    // Serve static files from dist/public
    const distPath = resolve(__dirname, "public");
    
    if (!fs.existsSync(distPath)) {
      throw new Error(`Could not find build directory: ${distPath}`);
    }
    
    app.use(express.static(distPath));
    
    // Catch-all handler for SPA
    app.get("*", (req, res) => {
      res.sendFile(resolve(distPath, "index.html"));
    });
    
    // Start server
    const port = parseInt(process.env.PORT || '3000', 10);
    server.listen(port, "0.0.0.0", () => {
      console.log(`${new Date().toLocaleTimeString()} [express] serving on port ${port}`);
    });
  });
}).catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
EOF

# Build the routes separately to ensure they work
log_info "Building routes module..."
npx esbuild server/routes.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/routes.js --external:express --external:openid-client --external:passport* --external:drizzle-orm --external:postgres --external:connect-pg-simple --external:express-session --external:memoizee --external:multer --external:csv-parser

# Build other server dependencies
log_info "Building server dependencies..."
npx esbuild server/storage.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/storage.js --external:drizzle-orm --external:postgres
npx esbuild server/db.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/db.js --external:drizzle-orm --external:postgres --external:@neondatabase/serverless
npx esbuild server/replitAuth.ts --platform=node --packages=external --bundle --format=esm --outfile=dist/replitAuth.js --external:openid-client --external:passport* --external:express-session --external:connect-pg-simple --external:memoizee

# Copy shared schema
log_info "Copying shared modules..."
mkdir -p dist/shared
cp shared/schema.ts dist/shared/

# Verify all required files exist
log_info "Verifying build..."
required_files=("dist/public/index.html" "dist/index.js" "dist/routes.js" "dist/storage.js" "dist/db.js" "dist/replitAuth.js")

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Build verification failed: $file not found"
        exit 1
    fi
done

log_info "✓ All build files verified"

# Run database migrations if DATABASE_URL is available
if [ -n "$DATABASE_URL" ]; then
    log_info "Running database migrations..."
    npm run db:push
else
    log_warn "DATABASE_URL not set - skipping database migrations"
fi

# Clean up dev dependencies to save space (optional)
if [ "$CLEAN_DEV_DEPS" = "true" ]; then
    log_info "Cleaning dev dependencies..."
    npm prune --production
fi

log_info "✓ Production build completed successfully!"
echo
echo "To start the production server:"
echo "  NODE_ENV=production PORT=3000 node dist/index.js"
echo
echo "Build artifacts:"
echo "  Frontend: dist/public/"
echo "  Server: dist/index.js"
echo "  Size: $(du -sh dist/ | cut -f1)"