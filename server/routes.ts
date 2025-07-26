import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { setupAuth, isAuthenticated } from "./replitAuth";
import { insertFlightSchema, insertAirportSchema, insertAirlineSchema } from "@shared/schema";
import { z } from "zod";
import multer from "multer";
import csv from "csv-parser";
import { Readable } from "stream";

const upload = multer({ storage: multer.memoryStorage() });

export async function registerRoutes(app: Express): Promise<Server> {
  // Auth middleware
  await setupAuth(app);

  // Auth routes
  app.get('/api/auth/user', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const user = await storage.getUser(userId);
      res.json(user);
    } catch (error) {
      console.error("Error fetching user:", error);
      res.status(500).json({ message: "Failed to fetch user" });
    }
  });

  // Flight routes
  app.get('/api/flights', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const flights = await storage.getFlights(userId);
      res.json(flights);
    } catch (error) {
      console.error("Error fetching flights:", error);
      res.status(500).json({ message: "Failed to fetch flights" });
    }
  });

  app.get('/api/flights/:id', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const flight = await storage.getFlight(req.params.id, userId);
      if (!flight) {
        return res.status(404).json({ message: "Flight not found" });
      }
      res.json(flight);
    } catch (error) {
      console.error("Error fetching flight:", error);
      res.status(500).json({ message: "Failed to fetch flight" });
    }
  });

  app.post('/api/flights', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const flightData = insertFlightSchema.parse(req.body);
      
      const flight = await storage.createFlight({
        ...flightData,
        userId,
      });
      
      res.status(201).json(flight);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid flight data", errors: error.errors });
      }
      console.error("Error creating flight:", error);
      res.status(500).json({ message: "Failed to create flight" });
    }
  });

  app.put('/api/flights/:id', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const flightData = insertFlightSchema.partial().parse(req.body);
      
      const flight = await storage.updateFlight(req.params.id, userId, flightData);
      if (!flight) {
        return res.status(404).json({ message: "Flight not found" });
      }
      
      res.json(flight);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid flight data", errors: error.errors });
      }
      console.error("Error updating flight:", error);
      res.status(500).json({ message: "Failed to update flight" });
    }
  });

  app.delete('/api/flights/:id', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const success = await storage.deleteFlight(req.params.id, userId);
      if (!success) {
        return res.status(404).json({ message: "Flight not found" });
      }
      res.status(204).send();
    } catch (error) {
      console.error("Error deleting flight:", error);
      res.status(500).json({ message: "Failed to delete flight" });
    }
  });

  // CSV Import route
  app.post('/api/flights/import-csv', isAuthenticated, upload.single('csvFile'), async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      
      if (!req.file) {
        return res.status(400).json({ message: "No CSV file provided" });
      }

      const csvData: any[] = [];
      const stream = Readable.from(req.file.buffer);
      
      stream
        .pipe(csv())
        .on('data', (data) => csvData.push(data))
        .on('end', async () => {
          try {
            const flights = [];
            
            for (const row of csvData) {
              // Parse CSV row according to the provided format
              const flightData = {
                date: new Date(row.Date),
                flightNumber: row['Flight number'],
                fromAirport: row.From,
                toAirport: row.To,
                fromAirportCode: extractAirportCode(row.From),
                toAirportCode: extractAirportCode(row.To),
                departureTime: row['Dep time'],
                arrivalTime: row['Arr time'],
                duration: row.Duration,
                airline: row.Airline,
                aircraftType: row.Aircraft,
                registration: row.Registration,
                seatNumber: row['Seat number'],
                seatType: row['Seat type'],
                flightClass: row['Flight class'],
                flightReason: row['Flight reason'],
                notes: row.Note,
                userId,
              };

              const flight = await storage.createFlight(flightData);
              flights.push(flight);
            }

            res.json({ 
              message: `Successfully imported ${flights.length} flights`,
              flights: flights.length
            });
          } catch (error) {
            console.error("Error processing CSV data:", error);
            res.status(500).json({ message: "Failed to process CSV data" });
          }
        })
        .on('error', (error) => {
          console.error("Error parsing CSV:", error);
          res.status(400).json({ message: "Invalid CSV format" });
        });
    } catch (error) {
      console.error("Error importing CSV:", error);
      res.status(500).json({ message: "Failed to import CSV" });
    }
  });

  // Statistics route
  app.get('/api/stats', isAuthenticated, async (req: any, res) => {
    try {
      const userId = req.user.claims.sub;
      const stats = await storage.getFlightStats(userId);
      res.json(stats);
    } catch (error) {
      console.error("Error fetching statistics:", error);
      res.status(500).json({ message: "Failed to fetch statistics" });
    }
  });

  // Airport routes
  app.get('/api/airports', async (req, res) => {
    try {
      const airports = await storage.getAirports();
      res.json(airports);
    } catch (error) {
      console.error("Error fetching airports:", error);
      res.status(500).json({ message: "Failed to fetch airports" });
    }
  });

  // Airline routes
  app.get('/api/airlines', async (req, res) => {
    try {
      const airlines = await storage.getAirlines();
      res.json(airlines);
    } catch (error) {
      console.error("Error fetching airlines:", error);
      res.status(500).json({ message: "Failed to fetch airlines" });
    }
  });

  const httpServer = createServer(app);
  return httpServer;
}

// Helper function to extract airport code from airport string
function extractAirportCode(airportString: string): string | null {
  const match = airportString.match(/\(([A-Z]{3})\//);
  return match ? match[1] : null;
}
