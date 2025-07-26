-- FlightTool Database Initialization Script
-- This script sets up the initial database configuration

-- Ensure the database exists (this might be redundant but safe)
SELECT 'CREATE DATABASE flighttool'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'flighttool');

-- Connect to the flighttool database
\c flighttool;

-- Create necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Grant necessary permissions to the flighttool user
GRANT ALL PRIVILEGES ON DATABASE flighttool TO flighttool;
GRANT ALL PRIVILEGES ON SCHEMA public TO flighttool;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO flighttool;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO flighttool;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO flighttool;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO flighttool;

-- Create indexes for better performance (will be created by Drizzle, but included for reference)
-- These will be created automatically when the schema is pushed