# Proxmox Container Database Configuration

## Current Environment Status

You are currently running FlightTool in **development mode** which uses the Neon cloud database:
```
DATABASE_URL=postgresql://neondb_owner:npg_tTKY49vaPZXn@ep-still-cloud-ad719t6f.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require
```

For your **Proxmox container deployment**, you should use the **local PostgreSQL database** that gets installed by the `proxmox-setup.sh` script.

## Proxmox Database Configuration

When you deploy to your Proxmox container, the setup script creates:

1. **Local PostgreSQL Installation**
   - Database: `flighttool`
   - User: `flighttool` 
   - Password: (set during setup)
   - Host: `localhost`
   - Port: `5432`

2. **Environment Configuration**
   ```bash
   DATABASE_URL=postgresql://flighttool:YOUR_PASSWORD@localhost:5432/flighttool
   ```

## Steps to Switch to Local Database

### Option 1: Deploy to Proxmox Container (Recommended)

1. Run the Proxmox setup script:
   ```bash
   chmod +x proxmox-setup.sh
   sudo ./proxmox-setup.sh
   ```

2. The script will:
   - Create LXC container
   - Install local PostgreSQL
   - Configure database with local credentials
   - Deploy FlightTool with correct DATABASE_URL

### Option 2: Configure Local PostgreSQL in Current Environment

If you want to test with local PostgreSQL in your current setup:

1. Install PostgreSQL:
   ```bash
   sudo apt update
   sudo apt install postgresql postgresql-contrib
   ```

2. Configure database:
   ```bash
   sudo -u postgres psql << EOF
   CREATE DATABASE flighttool;
   CREATE USER flighttool WITH PASSWORD 'your_password_here';
   GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
   ALTER USER flighttool CREATEDB;
   \q
   EOF
   ```

3. Update your environment:
   ```bash
   export DATABASE_URL="postgresql://flighttool:your_password_here@localhost:5432/flighttool"
   ```

4. Restart the application to use the new database.

## Database Differences

| Feature | Neon (Cloud) | Local PostgreSQL |
|---------|--------------|------------------|
| **Location** | External cloud | Container/local |
| **Performance** | Network latency | Direct local access |
| **Security** | TLS required | Local connections |
| **Backup** | Managed by Neon | Manual/scripted |
| **Cost** | Paid service | Free local |
| **Reliability** | Internet dependent | Local control |

## Recommendation

For your Proxmox production deployment, use the **local PostgreSQL database** as configured in the `proxmox-setup.sh` script. This provides:

- Better performance (no network latency)
- Full control over your data
- No external dependencies
- Included in your container backups
- No ongoing cloud database costs

The authentication and session management will work identically with both database configurations.