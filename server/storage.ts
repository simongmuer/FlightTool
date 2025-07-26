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
      .orderBy(desc(flights.date));
  }

  async getFlight(id: string, userId: string): Promise<Flight | undefined> {
    const [flight] = await db
      .select()
      .from(flights)
      .where(and(eq(flights.id, id), eq(flights.userId, userId)));
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
      .where(and(eq(flights.id, id), eq(flights.userId, userId)))
      .returning();
    return flight;
  }

  async deleteFlight(id: string, userId: string): Promise<boolean> {
    const result = await db
      .delete(flights)
      .where(and(eq(flights.id, id), eq(flights.userId, userId)));
    return result.length > 0;
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
        fromAirport: flights.fromAirportCode,
        toAirport: flights.toAirportCode 
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
      .orderBy(desc(flights.date))
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

    // Get monthly activity for current year
    const monthlyActivityResult = await db
      .select({
        month: sql<string>`TO_CHAR(date, 'Mon')`,
        count: sql<number>`count(*)`
      })
      .from(flights)
      .where(and(
        eq(flights.userId, userId),
        sql`EXTRACT(YEAR FROM date) = EXTRACT(YEAR FROM CURRENT_DATE)`
      ))
      .groupBy(sql`TO_CHAR(date, 'Mon')`, sql`EXTRACT(MONTH FROM date)`)
      .orderBy(sql`EXTRACT(MONTH FROM date)`);

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

export const storage = new DatabaseStorage();
