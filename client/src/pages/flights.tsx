import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";
import { isUnauthorizedError } from "@/lib/authUtils";
import Sidebar from "@/components/sidebar";
import FlightCard from "@/components/flight-card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Plus, Search } from "lucide-react";
import { useLocation } from "wouter";
import { useState } from "react";
import type { Flight } from "@shared/schema";

export default function Flights() {
  const { toast } = useToast();
  const { isAuthenticated, isLoading } = useAuth();
  const [, setLocation] = useLocation();
  const [searchTerm, setSearchTerm] = useState("");

  // Redirect to home if not authenticated
  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      toast({
        title: "Unauthorized",
        description: "You are logged out. Logging in again...",
        variant: "destructive",
      });
      setTimeout(() => {
        window.location.href = "/api/login";
      }, 500);
      return;
    }
  }, [isAuthenticated, isLoading, toast]);

  const { data: flights, isLoading: flightsLoading } = useQuery({
    queryKey: ["/api/flights"],
    retry: false,
    enabled: isAuthenticated,
  });

  const filteredFlights = flights?.filter((flight: Flight) =>
    flight.flightNumber.toLowerCase().includes(searchTerm.toLowerCase()) ||
    flight.fromAirport.toLowerCase().includes(searchTerm.toLowerCase()) ||
    flight.toAirport.toLowerCase().includes(searchTerm.toLowerCase()) ||
    flight.airline.toLowerCase().includes(searchTerm.toLowerCase())
  ) || [];

  if (isLoading || !isAuthenticated) {
    return null;
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <Sidebar />
      
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Header */}
        <header className="bg-white shadow-sm border-b border-slate-200 px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-bold text-slate-900">My Flights</h2>
              <p className="text-sm text-slate-600">Manage and view all your flight records</p>
            </div>
            <div className="flex items-center space-x-4">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-slate-400 w-4 h-4" />
                <Input
                  placeholder="Search flights..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10 w-64"
                />
              </div>
              <Button onClick={() => setLocation("/add-flight")} className="bg-aviation-blue hover:bg-blue-700">
                <Plus className="w-4 h-4 mr-2" />
                Add Flight
              </Button>
            </div>
          </div>
        </header>

        {/* Main Content */}
        <main className="flex-1 overflow-y-auto p-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between">
                Flight History
                <span className="text-sm font-normal text-slate-500">
                  {filteredFlights.length} of {flights?.length || 0} flights
                </span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              {flightsLoading ? (
                <div className="space-y-4">
                  {[...Array(5)].map((_, i) => (
                    <div key={i} className="animate-pulse flex items-center space-x-4 p-4 border border-slate-200 rounded-lg">
                      <div className="w-12 h-12 bg-slate-200 rounded-lg"></div>
                      <div className="flex-1 space-y-2">
                        <div className="h-4 bg-slate-200 rounded w-1/3"></div>
                        <div className="h-3 bg-slate-200 rounded w-1/2"></div>
                      </div>
                      <div className="space-y-2">
                        <div className="h-4 bg-slate-200 rounded w-20"></div>
                        <div className="h-3 bg-slate-200 rounded w-16"></div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : filteredFlights.length > 0 ? (
                <div className="space-y-4">
                  {filteredFlights.map((flight: Flight) => (
                    <FlightCard key={flight.id} flight={flight} />
                  ))}
                </div>
              ) : flights?.length === 0 ? (
                <div className="text-center py-12">
                  <div className="w-16 h-16 bg-slate-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Plus className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-medium text-slate-900 mb-2">No flights yet</h3>
                  <p className="text-slate-500 mb-6">Get started by adding your first flight or importing from CSV</p>
                  <div className="flex justify-center space-x-4">
                    <Button onClick={() => setLocation("/add-flight")} className="bg-aviation-blue hover:bg-blue-700">
                      <Plus className="w-4 h-4 mr-2" />
                      Add Flight
                    </Button>
                    <Button onClick={() => setLocation("/import")} variant="outline">
                      Import CSV
                    </Button>
                  </div>
                </div>
              ) : (
                <div className="text-center py-12">
                  <div className="w-16 h-16 bg-slate-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <Search className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-medium text-slate-900 mb-2">No flights match your search</h3>
                  <p className="text-slate-500">Try adjusting your search terms</p>
                </div>
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  );
}
