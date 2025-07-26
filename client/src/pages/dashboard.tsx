import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";
import { isUnauthorizedError } from "@/lib/authUtils";
import Sidebar from "@/components/sidebar";
import StatsCard from "@/components/stats-card";
import FlightCard from "@/components/flight-card";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Plane, Globe, MapPin, Building, Plus, Download } from "lucide-react";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, ResponsiveContainer } from "recharts";
import { useLocation } from "wouter";

export default function Dashboard() {
  const { toast } = useToast();
  const { isAuthenticated, isLoading } = useAuth();
  const [, setLocation] = useLocation();

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

  const { data: stats, isLoading: statsLoading } = useQuery({
    queryKey: ["/api/stats"],
    retry: false,
    enabled: isAuthenticated,
  });

  const handleAddFlight = () => {
    setLocation("/add-flight");
  };

  const handleExport = () => {
    // TODO: Implement CSV export
    toast({
      title: "Export",
      description: "CSV export functionality coming soon!",
    });
  };

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
              <h2 className="text-2xl font-bold text-slate-900">Dashboard</h2>
              <p className="text-sm text-slate-600">Welcome back! Here's your flight summary.</p>
            </div>
            <div className="flex items-center space-x-4">
              <Button onClick={handleAddFlight} className="bg-aviation-blue hover:bg-blue-700">
                <Plus className="w-4 h-4 mr-2" />
                Add Flight
              </Button>
              <Button onClick={handleExport} variant="outline">
                <Download className="w-4 h-4 mr-2" />
                Export
              </Button>
            </div>
          </div>
        </header>

        {/* Main Content */}
        <main className="flex-1 overflow-y-auto p-6">
          {/* Statistics Cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
            <StatsCard
              title="Total Flights"
              value={stats?.totalFlights || 0}
              icon={<Plane className="w-6 h-6 text-aviation-blue" />}
              trend="+12%"
              trendLabel="vs last year"
              loading={statsLoading}
            />
            <StatsCard
              title="Distance Flown"
              value={stats?.totalDistance || 0}
              suffix="miles"
              icon={<Globe className="w-6 h-6 text-green-600" />}
              trend="+8%"
              trendLabel="vs last year"
              loading={statsLoading}
            />
            <StatsCard
              title="Airports Visited"
              value={stats?.airportsVisited || 0}
              icon={<MapPin className="w-6 h-6 text-purple-600" />}
              trend="+3"
              trendLabel="new this year"
              loading={statsLoading}
            />
            <StatsCard
              title="Airlines Flown"
              value={stats?.airlinesFlown || 0}
              icon={<Building className="w-6 h-6 text-orange-600" />}
              trendLabel="Lufthansa most used"
              loading={statsLoading}
            />
          </div>

          {/* Charts and Map Section */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
            {/* Flight Map */}
            <Card>
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle>Flight Routes</CardTitle>
                <Button variant="link" onClick={() => setLocation("/map")}>
                  View Full Map
                </Button>
              </CardHeader>
              <CardContent>
                <div className="map-container rounded-lg h-64 flex items-center justify-center text-white relative overflow-hidden">
                  <div className="text-center z-10">
                    <MapPin className="w-12 h-12 mb-3 opacity-80 mx-auto" />
                    <p className="text-lg font-medium">Interactive Flight Map</p>
                    <p className="text-sm opacity-75">
                      {stats?.airportsVisited || 0} airports • {stats?.totalFlights || 0} flights
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Monthly Activity Chart */}
            <Card>
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle>Monthly Activity</CardTitle>
                <select className="text-sm border border-slate-300 rounded-lg px-3 py-1">
                  <option value="2024">2024</option>
                  <option value="2023">2023</option>
                </select>
              </CardHeader>
              <CardContent>
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={stats?.monthlyActivity || []}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="month" />
                      <YAxis />
                      <Bar dataKey="count" fill="var(--primary)" />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Recent Flights and Top Airlines */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Recent Flights */}
            <Card className="lg:col-span-2">
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle>Recent Flights</CardTitle>
                <Button variant="link" onClick={() => setLocation("/flights")}>
                  View All
                </Button>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {stats?.recentFlights?.length ? (
                    stats.recentFlights.map((flight) => (
                      <FlightCard key={flight.id} flight={flight} compact />
                    ))
                  ) : (
                    <p className="text-slate-500 text-center py-8">
                      No flights yet. <Button variant="link" onClick={handleAddFlight}>Add your first flight</Button>
                    </p>
                  )}
                </div>
              </CardContent>
            </Card>

            {/* Top Airlines */}
            <Card>
              <CardHeader>
                <CardTitle>Top Airlines</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {stats?.topAirlines?.length ? (
                    stats.topAirlines.map((airline, index) => (
                      <div key={index} className="flex items-center justify-between">
                        <div className="flex items-center space-x-3">
                          <div className="w-8 h-8 bg-aviation-blue rounded-lg flex items-center justify-center text-white text-sm font-semibold">
                            {airline.airline.split(' ')[0].substring(0, 2).toUpperCase()}
                          </div>
                          <div>
                            <p className="text-sm font-medium text-slate-900">{airline.airline}</p>
                            <p className="text-xs text-slate-500">{airline.count} flights</p>
                          </div>
                        </div>
                        <div className="text-right">
                          <p className="text-sm font-semibold text-slate-900">{airline.percentage}%</p>
                        </div>
                      </div>
                    ))
                  ) : (
                    <p className="text-slate-500 text-center py-8">No data available</p>
                  )}
                </div>
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  );
}
