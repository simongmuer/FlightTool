# FlightTool Docker Deployment Guide

This guide provides an alternative containerized deployment using Docker, which can also run in LXC containers for additional isolation.

## Prerequisites

- **Docker and Docker Compose** installed
- **Basic understanding** of containerization
- **Domain name** (optional, for production)

## Quick Start with Docker

### 1. Create Dockerfile
```dockerfile
# Multi-stage build for FlightTool
FROM node:18-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY . .
RUN npm run build

# Production stage
FROM node:18-alpine AS production

WORKDIR /app

# Install PostgreSQL client for migrations
RUN apk add --no-cache postgresql-client

# Create non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S flighttool -u 1001

# Copy built application
COPY --from=builder --chown=flighttool:nodejs /app/dist ./dist
COPY --from=builder --chown=flighttool:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=flighttool:nodejs /app/package*.json ./

USER flighttool
EXPOSE 3000

CMD ["npm", "start"]
```

### 2. Create Docker Compose
```yaml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://flighttool:password@postgres:5432/flighttool
      - SESSION_SECRET=${SESSION_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped
    volumes:
      - app_logs:/app/logs

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=flighttool
      - POSTGRES_USER=flighttool
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U flighttool"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - app
    restart: unless-stopped

volumes:
  postgres_data:
  app_logs:
```

### 3. Deploy
```bash
# Create environment file
echo "SESSION_SECRET=$(openssl rand -base64 32)" > .env

# Build and start
docker-compose up -d

# Run migrations
docker-compose exec app npm run db:push
```

This provides a complete containerized solution that can run in any environment, including within LXC containers for additional isolation layers.