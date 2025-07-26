import {
  users,
  flights,
  airports,
  airlines,
  type User,
  type InsertUser,
  type Flight,
  type InsertFlight,
  type Airport,
  type InsertAirport,
  type Airline,
  type InsertAirline,
} from "@shared/schema";
import { db } from "./db";
import { eq, desc, and, sql } from "drizzle-orm";

export interface IStorage {
  // User operations for local authentication
  getUser(id: string): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  
  // Flight operations
  getFlights(userId: string): Promise<Flight[]>;
  getFlight(id: string, userId: string): Promise<Flight | undefined>;
  createFlight(flight: InsertFlight): Promise<Flight>;
  updateFlight(id: string, userId: string, flight: Partial<InsertFlight>): Promise<Flight | undefined>;
  deleteFlight(id: string, userId: string): Promise<boolean>;
  
  // Airport operations
  getAirports(): Promise<Airport[]>;
  getAirportByCode(code: string): Promise<Airport | undefined>;
  createAirport(airport: InsertAirport): Promise<Airport>;
  
  // Airline operations
  getAirlines(): Promise<Airline[]>;
  getAirlineByCode(code: string): Promise<Airline | undefined>;
  createAirline(airline: InsertAirline): Promise<Airline>;
  
  // Statistics
  getFlightStats(userId: string): Promise<{
    totalFlights: number;
    totalDistance: number;
    airportsVisited: number;
    airlinesFlown: number;
    recentFlights: Flight[];
    topAirlines: Array<{ airline: string; count: number; percentage: number }>;
    monthlyActivity: Array<{ month: string; count: number }>;
  }>;
}

export class DatabaseStorage implements IStorage {
  // User operations for local authentication
  async getUser(id: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user;
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    const [user] = await db.select().from(users).where(eq(users.username, username));
    return user;
  }

  async createUser(userData: InsertUser): Promise<User> {
    const [user] = await db
      .insert(users)
      .values(userData)
      .returning();
    return user;
  }

  // Flight operations
  async getFlights(userId: string): Promise<Flight[]> {
    return await db
      .select()
      .from(flights)
      .where(eq(flights.userId, userId))
      .orderBy(desc(flights.departureDate));
  }

  async getFlight(id: string, userId: string): Promise<Flight | undefined> {
    const [flight] = await db
      .select()
      .from(flights)
      .where(and(eq(flights.id, parseInt(id)), eq(flights.userId, userId)));
    return flight;
  }

  async createFlight(flight: InsertFlight): Promise<Flight> {
    const [newFlight] = await db.insert(flights).values(flight).returning();
    return newFlight;
  }

  async updateFlight(id: string, userId: string, flightData: Partial<InsertFlight>): Promise<Flight | undefined> {
    const [flight] = await db
      .update(flights)
      .set({ ...flightData, updatedAt: new Date() })
      .where(and(eq(flights.id, parseInt(id)), eq(flights.userId, userId)))
      .returning();
    return flight;
  }

  async deleteFlight(id: string, userId: string): Promise<boolean> {
    const result = await db
      .delete(flights)
      .where(and(eq(flights.id, parseInt(id)), eq(flights.userId, userId)));
    return result.changes > 0;
  }

  // Airport operations
  async getAirports(): Promise<Airport[]> {
    return await db.select().from(airports);
  }

  async getAirportByCode(code: string): Promise<Airport | undefined> {
    const [airport] = await db
      .select()
      .from(airports)
      .where(eq(airports.code, code));
    return airport;
  }

  async createAirport(airport: InsertAirport): Promise<Airport> {
    const [newAirport] = await db.insert(airports).values(airport).returning();
    return newAirport;
  }

  // Airline operations
  async getAirlines(): Promise<Airline[]> {
    return await db.select().from(airlines);
  }

  async getAirlineByCode(code: string): Promise<Airline | undefined> {
    const [airline] = await db
      .select()
      .from(airlines)
      .where(eq(airlines.code, code));
    return airline;
  }

  async createAirline(airline: InsertAirline): Promise<Airline> {
    const [newAirline] = await db.insert(airlines).values(airline).returning();
    return newAirline;
  }

  // Statistics
  async getFlightStats(userId: string) {
    // Get total flights
    const totalFlightsResult = await db
      .select({ count: sql<number>`count(*)` })
      .from(flights)
      .where(eq(flights.userId, userId));
    
    // Get unique airports visited
    const airportsVisitedResult = await db
      .selectDistinct({ 
        fromAirport: flights.fromAirport,
        toAirport: flights.toAirport 
      })
      .from(flights)
      .where(eq(flights.userId, userId));
    
    const uniqueAirports = new Set();
    airportsVisitedResult.forEach(result => {
      if (result.fromAirport) uniqueAirports.add(result.fromAirport);
      if (result.toAirport) uniqueAirports.add(result.toAirport);
    });

    // Get unique airlines
    const airlinesFlownResult = await db
      .selectDistinct({ airline: flights.airline })
      .from(flights)
      .where(eq(flights.userId, userId));

    // Get recent flights
    const recentFlights = await db
      .select()
      .from(flights)
      .where(eq(flights.userId, userId))
      .orderBy(desc(flights.departureDate))
      .limit(5);

    // Get top airlines
    const topAirlinesResult = await db
      .select({
        airline: flights.airline,
        count: sql<number>`count(*)`
      })
      .from(flights)
      .where(eq(flights.userId, userId))
      .groupBy(flights.airline)
      .orderBy(desc(sql`count(*)`))
      .limit(10);

    const totalFlights = totalFlightsResult[0]?.count || 0;
    const topAirlines = topAirlinesResult.map(item => ({
      airline: item.airline,
      count: item.count,
      percentage: totalFlights > 0 ? Math.round((item.count / totalFlights) * 100) : 0
    }));

    // Get monthly activity for current year - simplified for now
    const monthlyActivityResult: any[] = [];

    return {
      totalFlights,
      totalDistance: 0, // Calculate based on airport coordinates when available
      airportsVisited: uniqueAirports.size,
      airlinesFlown: airlinesFlownResult.length,
      recentFlights,
      topAirlines,
      monthlyActivity: monthlyActivityResult
    };
  }
}

// Initialize database schema on startup
async function initializeDatabase() {
  try {
    // Check if tables exist and create them if needed
    const tablesExist = await db.execute(sql`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'users'
      );
    `);
    
    if (!tablesExist[0]?.exists) {
      console.log("Creating database schema...");
      
      // Create sessions table
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS sessions (
          sid VARCHAR PRIMARY KEY,
          sess JSONB NOT NULL,
          expire TIMESTAMP NOT NULL
        );
      `);
      await db.execute(sql`CREATE INDEX IF NOT EXISTS IDX_session_expire ON sessions (expire);`);
      
      // Create users table
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS users (
          id VARCHAR PRIMARY KEY DEFAULT gen_random_uuid(),
          email VARCHAR UNIQUE,
          first_name VARCHAR,
          last_name VARCHAR,
          profile_image_url VARCHAR,
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW(),
          username VARCHAR UNIQUE NOT NULL,
          password VARCHAR NOT NULL
        );
      `);
      
      // Create airports table
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS airports (
          id SERIAL PRIMARY KEY,
          iata_code VARCHAR(3) UNIQUE,
          icao_code VARCHAR(4) UNIQUE,
          name VARCHAR NOT NULL,
          city VARCHAR,
          country VARCHAR,
          latitude DECIMAL(10,8),
          longitude DECIMAL(11,8),
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW()
        );
      `);
      
      // Create airlines table
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS airlines (
          id SERIAL PRIMARY KEY,
          iata_code VARCHAR(2) UNIQUE,
          icao_code VARCHAR(3) UNIQUE,
          name VARCHAR NOT NULL,
          country VARCHAR,
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW()
        );
      `);
      
      // Create flights table
      await db.execute(sql`
        CREATE TABLE IF NOT EXISTS flights (
          id SERIAL PRIMARY KEY,
          user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          flight_number VARCHAR,
          airline VARCHAR,
          from_airport VARCHAR NOT NULL,
          to_airport VARCHAR NOT NULL,
          departure_date DATE NOT NULL,
          departure_time TIME,
          arrival_date DATE,
          arrival_time TIME,
          aircraft_type VARCHAR,
          seat_number VARCHAR,
          flight_class VARCHAR,
          ticket_price DECIMAL(10,2),
          currency VARCHAR(3) DEFAULT 'USD',
          notes TEXT,
          created_at TIMESTAMP DEFAULT NOW(),
          updated_at TIMESTAMP DEFAULT NOW()
        );
      `);
      
      // Create indexes
      await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_flights_user_id ON flights(user_id);`);
      await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_flights_departure_date ON flights(departure_date);`);
      await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_airports_iata ON airports(iata_code);`);
      await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_airlines_iata ON airlines(iata_code);`);
      
      // Insert basic airport data
      const airportData = [
        ['JFK', 'KJFK', 'John F. Kennedy International Airport', 'New York', 'United States'],
        ['LAX', 'KLAX', 'Los Angeles International Airport', 'Los Angeles', 'United States'],
        ['LHR', 'EGLL', 'London Heathrow Airport', 'London', 'United Kingdom'],
        ['CDG', 'LFPG', 'Charles de Gaulle Airport', 'Paris', 'France'],
        ['NRT', 'RJAA', 'Narita International Airport', 'Tokyo', 'Japan'],
        ['DXB', 'OMDB', 'Dubai International Airport', 'Dubai', 'United Arab Emirates'],
        ['SIN', 'WSSS', 'Singapore Changi Airport', 'Singapore', 'Singapore'],
        ['FRA', 'EDDF', 'Frankfurt Airport', 'Frankfurt', 'Germany'],
        ['AMS', 'EHAM', 'Amsterdam Airport Schiphol', 'Amsterdam', 'Netherlands'],
        ['SYD', 'YSSY', 'Sydney Kingsford Smith Airport', 'Sydney', 'Australia']
      ];
      
      for (const [iata, icao, name, city, country] of airportData) {
        await db.execute(sql`
          INSERT INTO airports (iata_code, icao_code, name, city, country) 
          VALUES (${iata}, ${icao}, ${name}, ${city}, ${country})
          ON CONFLICT (iata_code) DO NOTHING;
        `);
      }
      
      // Insert basic airline data
      const airlineData = [
        ['AA', 'AAL', 'American Airlines', 'United States'],
        ['UA', 'UAL', 'United Airlines', 'United States'],
        ['DL', 'DAL', 'Delta Air Lines', 'United States'],
        ['BA', 'BAW', 'British Airways', 'United Kingdom'],
        ['AF', 'AFR', 'Air France', 'France'],
        ['LH', 'DLH', 'Lufthansa', 'Germany'],
        ['EK', 'UAE', 'Emirates', 'United Arab Emirates'],
        ['SQ', 'SIA', 'Singapore Airlines', 'Singapore'],
        ['QF', 'QFA', 'Qantas', 'Australia'],
        ['JL', 'JAL', 'Japan Airlines', 'Japan']
      ];
      
      for (const [iata, icao, name, country] of airlineData) {
        await db.execute(sql`
          INSERT INTO airlines (iata_code, icao_code, name, country) 
          VALUES (${iata}, ${icao}, ${name}, ${country})
          ON CONFLICT (iata_code) DO NOTHING;
        `);
      }
      
      console.log("Database schema created successfully");
    }
  } catch (error) {
    console.error("Database initialization error:", error);
    // Don't throw error - allow app to continue running
  }
}

export const storage = new DatabaseStorage();

// Initialize database on module load
initializeDatabase().catch(console.error);
