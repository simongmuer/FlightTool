# FlightTool Database Access Guide

This guide explains how to connect to your FlightTool PostgreSQL database locally via SSH.

## Your Current Database Configuration

Based on your FlightTool environment, here are your database connection details:

```bash
Host: ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech
Port: 5432
Database: neondb
User: neondb_owner
Password: [available in DATABASE_URL environment variable]
```

## Connection Methods

### 1. Direct Connection (if database allows external connections)

Since you're using Neon Database, you can connect directly without SSH tunneling:

```bash
# Using psql directly
psql -h ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech -p 5432 -U neondb_owner -d neondb

# Or using the full DATABASE_URL
psql $DATABASE_URL
```

### 2. SSH Tunnel Method (for server-based deployments)

If you need to connect through your server:

```bash
# Create SSH tunnel to your server
ssh -L 15432:ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech:5432 user@your-server.com

# Then connect locally
psql -h localhost -p 15432 -U neondb_owner -d neondb
```

### 3. Get Database URL from Server

To retrieve the complete database URL with password:

```bash
# SSH to your server and get the full DATABASE_URL
ssh user@your-server.com
echo $DATABASE_URL

# Copy the URL and use it locally
psql "postgresql://neondb_owner:password@ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech:5432/neondb"
```

## GUI Database Tools

### pgAdmin Configuration
- **Host:** ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech
- **Port:** 5432
- **Database:** neondb
- **Username:** neondb_owner
- **Password:** [from DATABASE_URL on server]
- **SSL Mode:** Require (recommended for Neon)

### DBeaver Configuration
1. Create new PostgreSQL connection
2. **Server Host:** ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech
3. **Port:** 5432
4. **Database:** neondb
5. **Username:** neondb_owner
6. **Password:** [from your server's DATABASE_URL]
7. **SSL:** Enable SSL

## Useful Commands

### Check FlightTool Tables
```sql
-- View all tables
\dt

-- Check users
SELECT username, email, first_name, last_name, created_at FROM users;

-- View flights
SELECT flight_number, from_airport, to_airport, date, airline FROM flights LIMIT 10;

-- Get statistics
SELECT 
  (SELECT COUNT(*) FROM users) as total_users,
  (SELECT COUNT(*) FROM flights) as total_flights,
  (SELECT COUNT(*) FROM sessions WHERE expire > NOW()) as active_sessions;
```

### Backup Commands
```bash
# Create backup
pg_dump "postgresql://neondb_owner:password@ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech:5432/neondb" > flighttool_backup.sql

# Restore backup
psql "postgresql://neondb_owner:password@ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech:5432/neondb" < flighttool_backup.sql
```

## Security Notes for Neon Database

1. **SSL/TLS:** Always use SSL connections (enabled by default)
2. **IP Restrictions:** Configure allowed IP addresses in Neon dashboard
3. **Connection Pooling:** Neon provides built-in connection pooling
4. **Monitoring:** Use Neon dashboard for connection monitoring

## Troubleshooting

### Connection Issues
```bash
# Test basic connectivity
pg_isready -h ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech -p 5432

# Check if database accepts connections
telnet ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech 5432
```

### Get Password from Server
```bash
# SSH to your server
ssh user@your-server.com

# Extract password from DATABASE_URL
echo $DATABASE_URL | sed 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/'
```

## Environment-Specific Access

### For Local Development
```bash
# Copy DATABASE_URL from server to local environment
scp user@your-server.com:/path/to/flighttool/.env ./
source .env
psql $DATABASE_URL
```

### For Production Server Access
```bash
# Connect directly on the server
ssh user@your-server.com
cd /path/to/flighttool
psql $DATABASE_URL
```

Since you're using Neon Database (a cloud PostgreSQL service), you can typically connect directly without SSH tunneling, making database access much simpler than traditional server-hosted databases.