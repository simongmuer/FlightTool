import { useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/use-toast";
import Sidebar from "@/components/sidebar";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Map } from "lucide-react";

export default function FlightMap() {
  const { toast } = useToast();
  const { isAuthenticated, isLoading } = useAuth();

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
              <h2 className="text-2xl font-bold text-slate-900">Flight Map</h2>
              <p className="text-sm text-slate-600">Visualize your flight routes and destinations</p>
            </div>
          </div>
        </header>

        {/* Main Content */}
        <main className="flex-1 overflow-y-auto p-6">
          <Card className="h-full">
            <CardHeader>
              <CardTitle>Interactive Flight Map</CardTitle>
            </CardHeader>
            <CardContent className="h-full">
              <div className="map-container rounded-lg h-full flex items-center justify-center text-white relative overflow-hidden min-h-96">
                <div className="text-center z-10">
                  <Map className="w-16 h-16 mb-4 opacity-80 mx-auto" />
                  <p className="text-xl font-medium mb-2">Interactive Flight Map</p>
                  <p className="text-sm opacity-75">
                    Map integration with React Leaflet coming soon!
                  </p>
                  <p className="text-xs opacity-60 mt-4">
                    This will show your flight routes, visited airports, and travel patterns
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  );
}
