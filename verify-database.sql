-- FlightTool Database Verification Script
-- Run this in your Proxmox container to verify the database structure

-- Check if all required tables exist
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Check flights table structure (this should include the 'date' column)
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'flights'
ORDER BY ordinal_position;

-- Verify the specific 'date' column in flights table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name = 'flights' 
AND column_name = 'date';

-- Check if there are any flights in the table
SELECT COUNT(*) as flight_count FROM flights;

-- Test a simple query that would cause the error
SELECT 
  user_id,
  date,
  flight_number
FROM flights 
LIMIT 1;