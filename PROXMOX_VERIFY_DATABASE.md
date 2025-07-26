# Verify Database Structure in Proxmox Container

## Quick Database Verification

To verify that the "date" column exists in your Proxmox deployment, connect to your container and run these commands:

### 1. Connect to your Proxmox container
```bash
pct enter YOUR_CONTAINER_ID
```

### 2. Connect to PostgreSQL
```bash
sudo -u postgres psql flighttool
```

### 3. Check flights table structure
```sql
\d flights
```

This should show you all columns including:
- `date | timestamp without time zone | not null`

### 4. Verify specific date column
```sql
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'flights' AND column_name = 'date';
```

Expected result:
```
 column_name |         data_type          
-------------+---------------------------
 date        | timestamp without time zone
```

### 5. Test the problematic query
```sql
SELECT COUNT(*) FROM flights WHERE EXTRACT(YEAR FROM date) = 2025;
```

## Expected Database Schema

Your flights table should have these columns:
- `id` (varchar, primary key)
- `user_id` (varchar, not null)
- **`date` (timestamp, not null)** ← This is the column causing the error
- `flight_number` (varchar, not null)
- `from_airport` (varchar, not null)
- `to_airport` (varchar, not null)
- `from_airport_code` (varchar)
- `to_airport_code` (varchar)
- `departure_time` (varchar)
- `arrival_time` (varchar)
- `duration` (varchar)
- `airline` (varchar, not null)
- `aircraft_type` (varchar)
- `registration` (varchar)
- `seat_number` (varchar)
- `seat_type` (varchar)
- `flight_class` (varchar)
- `flight_reason` (varchar)
- `notes` (text)
- `created_at` (timestamp)
- `updated_at` (timestamp)

## If the Date Column is Missing

If the `date` column doesn't exist, run this to create it:

```sql
ALTER TABLE flights ADD COLUMN date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP;
```

## If Tables Don't Exist

If the tables are missing entirely, the application should create them automatically on startup. Check the application logs for schema creation messages.

You can also manually run the schema creation by restarting the FlightTool service:

```bash
sudo systemctl restart flighttool
sudo journalctl -u flighttool -f
```

Look for messages like "Creating database schema..." in the logs.