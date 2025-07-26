import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Plane, Map, BarChart3, Upload } from "lucide-react";

export default function Landing() {
  const handleLogin = () => {
    window.location.href = "/api/login";
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50">
      <div className="container mx-auto px-4 py-16">
        {/* Header */}
        <div className="text-center mb-16">
          <div className="flex items-center justify-center space-x-3 mb-6">
            <div className="w-16 h-16 bg-aviation-blue rounded-xl flex items-center justify-center">
              <Plane className="w-8 h-8 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-slate-900">FlightTool</h1>
              <p className="text-lg text-slate-600">Personal Flight Tracking</p>
            </div>
          </div>
          <p className="text-xl text-slate-600 max-w-2xl mx-auto">
            Track your flights, visualize your journeys, and analyze your travel statistics 
            with our comprehensive flight tracking application.
          </p>
        </div>

        {/* Features */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
          <Card className="text-center">
            <CardHeader>
              <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                <Plane className="w-6 h-6 text-aviation-blue" />
              </div>
              <CardTitle className="text-lg">Flight Management</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>
                Add, edit, and organize all your flight information in one place
              </CardDescription>
            </CardContent>
          </Card>

          <Card className="text-center">
            <CardHeader>
              <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                <Map className="w-6 h-6 text-green-600" />
              </div>
              <CardTitle className="text-lg">Interactive Maps</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>
                Visualize your flight routes and visited airports on interactive maps
              </CardDescription>
            </CardContent>
          </Card>

          <Card className="text-center">
            <CardHeader>
              <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                <BarChart3 className="w-6 h-6 text-purple-600" />
              </div>
              <CardTitle className="text-lg">Statistics</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>
                Comprehensive analytics including distance, airlines, and travel patterns
              </CardDescription>
            </CardContent>
          </Card>

          <Card className="text-center">
            <CardHeader>
              <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center mx-auto mb-4">
                <Upload className="w-6 h-6 text-orange-600" />
              </div>
              <CardTitle className="text-lg">CSV Import</CardTitle>
            </CardHeader>
            <CardContent>
              <CardDescription>
                Import your existing flight data from CSV files for quick setup
              </CardDescription>
            </CardContent>
          </Card>
        </div>

        {/* CTA */}
        <div className="text-center">
          <Button 
            onClick={handleLogin}
            size="lg"
            className="bg-aviation-blue hover:bg-blue-700 text-white px-8 py-3 text-lg"
          >
            Get Started
          </Button>
          <p className="text-sm text-slate-500 mt-4">
            Sign in to start tracking your flights
          </p>
        </div>
      </div>
    </div>
  );
}
