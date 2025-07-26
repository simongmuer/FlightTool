import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { ArrowRight, MoreHorizontal } from "lucide-react";
import type { Flight } from "@shared/schema";
import { format } from "date-fns";

interface FlightCardProps {
  flight: Flight;
  compact?: boolean;
}

export default function FlightCard({ flight, compact = false }: FlightCardProps) {
  const getAirlineCode = (airline: string) => {
    // Extract airline code from airline string
    const match = airline.match(/\(([A-Z0-9]+)\//);
    return match ? match[1] : airline.substring(0, 2).toUpperCase();
  };

  const formatDate = (date: Date | string) => {
    return format(new Date(date), compact ? "MMM dd, yyyy" : "MMM dd, yyyy • HH:mm");
  };

  const getAirportCode = (airport: string) => {
    return flight.fromAirportCode || airport.substring(0, 3).toUpperCase();
  };

  return (
    <Card className="hover:bg-slate-50 transition-colors">
      <CardContent className="p-4">
        <div className="flex items-center space-x-4">
          {/* Airline Logo */}
          <div className="w-12 h-12 bg-aviation-blue rounded-lg flex items-center justify-center text-white font-semibold text-sm">
            {getAirlineCode(flight.airline)}
          </div>

          {/* Flight Info */}
          <div className="flex-1">
            <div className="flex items-center space-x-2 mb-1">
              <span className="font-medium text-slate-900">
                {flight.fromAirportCode || getAirportCode(flight.fromAirport)}
              </span>
              <ArrowRight className="w-4 h-4 text-slate-400" />
              <span className="font-medium text-slate-900">
                {flight.toAirportCode || getAirportCode(flight.toAirport)}
              </span>
              <span className="text-sm text-slate-500">{flight.flightNumber}</span>
            </div>
            <p className="text-sm text-slate-600">
              {formatDate(flight.date)}
              {flight.duration && ` • ${flight.duration}`}
            </p>
          </div>

          {/* Aircraft & Seat */}
          <div className="text-right">
            {flight.aircraftType && (
              <p className="text-sm font-medium text-slate-900">{flight.aircraftType}</p>
            )}
            {flight.seatNumber && (
              <p className="text-xs text-slate-500">{flight.seatNumber}</p>
            )}
          </div>

          {/* Actions */}
          {!compact && (
            <Button variant="ghost" size="sm">
              <MoreHorizontal className="w-4 h-4" />
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
