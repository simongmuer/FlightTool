-- Database Migration Fix for Proxmox Deployment
-- This script fixes the missing 'date' column issue in your flights table

-- OPTION 1: Add the missing 'date' column to your existing flights table
-- This preserves your existing data and adds the required column
ALTER TABLE flights ADD COLUMN date timestamp NOT NULL DEFAULT departure_date;

-- Update the date column to use departure_date values
UPDATE flights SET date = departure_date WHERE date IS NULL;

-- OPTION 2: Alternative - Create a proper view that maps your columns
-- This creates a view that matches what the application expects
CREATE OR REPLACE VIEW flights_compatible AS
SELECT 
    id,
    user_id,
    departure_date as date,  -- Map departure_date to date
    flight_number,
    airline,
    from_airport,
    to_airport,
    departure_date,
    departure_time,
    arrival_date,
    arrival_time,
    aircraft_type,
    seat_number,
    flight_class,
    ticket_price,
    currency,
    notes,
    created_at,
    updated_at
FROM flights;

-- OPTION 3: For completely fresh start (WARNING: This deletes all flight data)
-- DROP TABLE flights;
-- Then let the application recreate the table with the correct schema

-- Recommended: Use OPTION 1 to add the missing date column
-- Run this command in your Proxmox container:
-- sudo -u postgres psql flighttool < DATABASE_MIGRATION_FIX.sql