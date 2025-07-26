# Multi-stage build for FlightTool
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Install system dependencies
RUN apk add --no-cache \
    postgresql-client \
    curl \
    ca-certificates

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S flighttool -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=flighttool:nodejs /app/dist ./dist
COPY --from=builder --chown=flighttool:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=flighttool:nodejs /app/package*.json ./
COPY --from=builder --chown=flighttool:nodejs /app/drizzle.config.ts ./

# Create logs directory
RUN mkdir -p /app/logs && \
    chown -R flighttool:nodejs /app/logs

# Switch to non-root user
USER flighttool

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Start the application
CMD ["npm", "start"]