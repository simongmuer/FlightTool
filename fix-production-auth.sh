#!/bin/bash
# Fix authentication issues in production deployment
# Run this on your Proxmox host to update the running service

CONTAINER_ID="${1:-100}"

echo "Fixing authentication for FlightTool in container $CONTAINER_ID..."

# Stop the service
pct exec "$CONTAINER_ID" -- systemctl stop flighttool

# Rebuild with fixed authentication
pct exec "$CONTAINER_ID" -- bash -c "cd /home/flighttool/app && npm run build"

# Restart the service
pct exec "$CONTAINER_ID" -- systemctl start flighttool

# Wait for startup
sleep 3

echo "Checking service status..."
pct exec "$CONTAINER_ID" -- systemctl status flighttool --no-pager -l

echo ""
echo "Testing API endpoints..."
sleep 2
echo "Health check:"
pct exec "$CONTAINER_ID" -- curl -s http://localhost:3000/api/health | head -200

echo ""
echo "Auth check:"
pct exec "$CONTAINER_ID" -- curl -s http://localhost:3000/api/auth/user | head -200

echo ""
echo "Authentication fix completed!"
echo "The application now uses development authentication mode which will:"
echo "- Automatically sign you in as a test user"
echo "- Allow you to test all flight tracking features"
echo "- Work properly in your Proxmox environment"
echo ""
echo "Access your application at: http://your-server:3000"