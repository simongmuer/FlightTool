import { sql } from 'drizzle-orm';
import {
  index,
  jsonb,
  pgTable,
  timestamp,
  varchar,
  text,
  decimal,
  integer,
  date,
  time,
} from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

// Session storage table (required for Replit Auth)
export const sessions = pgTable(
  "sessions",
  {
    sid: varchar("sid").primaryKey(),
    sess: jsonb("sess").notNull(),
    expire: timestamp("expire").notNull(),
  },
  (table) => [index("IDX_session_expire").on(table.expire)],
);

// User storage table for local authentication
export const users = pgTable("users", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  username: varchar("username").unique().notNull(),
  password: varchar("password").notNull(),
  email: varchar("email").unique(),
  firstName: varchar("first_name"),
  lastName: varchar("last_name"),
  profileImageUrl: varchar("profile_image_url"),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Flights table - updated to match your existing database structure
export const flights = pgTable("flights", {
  id: integer("id").primaryKey().generatedAlwaysAsIdentity(),
  userId: varchar("user_id").notNull(),
  flightNumber: varchar("flight_number").notNull(),
  airline: varchar("airline").notNull(),
  fromAirport: varchar("from_airport").notNull(),
  toAirport: varchar("to_airport").notNull(),
  departureDate: date("departure_date").notNull(),
  departureTime: time("departure_time"),
  arrivalDate: date("arrival_date").notNull(),
  arrivalTime: time("arrival_time"),
  aircraftType: varchar("aircraft_type").default(""),
  seatNumber: varchar("seat_number").default(""),
  flightClass: varchar("flight_class").default(""),
  ticketPrice: decimal("ticket_price", { precision: 10, scale: 2 }),
  currency: varchar("currency", { length: 3 }).default("USD"),
  notes: text("notes").default(""),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

// Airport data table
export const airports = pgTable("airports", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  code: varchar("code").notNull().unique(),
  name: varchar("name").notNull(),
  city: varchar("city"),
  country: varchar("country"),
  latitude: decimal("latitude"),
  longitude: decimal("longitude"),
  createdAt: timestamp("created_at").defaultNow(),
});

// Airline data table
export const airlines = pgTable("airlines", {
  id: varchar("id").primaryKey().default(sql`gen_random_uuid()`),
  code: varchar("code").notNull().unique(),
  name: varchar("name").notNull(),
  createdAt: timestamp("created_at").defaultNow(),
});

// Schema types and validators
export type InsertUser = typeof users.$inferInsert;
export type User = typeof users.$inferSelect;

export type InsertFlight = typeof flights.$inferInsert;
export type Flight = typeof flights.$inferSelect;

export type InsertAirport = typeof airports.$inferInsert;
export type Airport = typeof airports.$inferSelect;

export type InsertAirline = typeof airlines.$inferInsert;
export type Airline = typeof airlines.$inferSelect;

export const insertFlightSchema = createInsertSchema(flights).omit({
  id: true,
  userId: true,
  createdAt: true,
  updatedAt: true,
});

export const insertAirportSchema = createInsertSchema(airports).omit({
  id: true,
  createdAt: true,
});

export const insertAirlineSchema = createInsertSchema(airlines).omit({
  id: true,
  createdAt: true,
});

export type InsertFlightData = z.infer<typeof insertFlightSchema>;
export type InsertAirportData = z.infer<typeof insertAirportSchema>;
export type InsertAirlineData = z.infer<typeof insertAirlineSchema>;
