import { useAuth } from "@/hooks/useAuth";
import { useLocation } from "wouter";
import { Button } from "@/components/ui/button";
import { 
  Plane, 
  BarChart3, 
  List, 
  Map, 
  Plus, 
  Upload, 
  User, 
  Settings,
  MoreVertical 
} from "lucide-react";

export default function Sidebar() {
  const { user } = useAuth();
  const [location, setLocation] = useLocation();

  const handleLogout = () => {
    window.location.href = "/api/logout";
  };

  const menuItems = [
    { path: "/", icon: <BarChart3 className="w-5 h-5" />, label: "Dashboard" },
    { path: "/flights", icon: <List className="w-5 h-5" />, label: "My Flights" },
    { path: "/map", icon: <Map className="w-5 h-5" />, label: "Flight Map" },
    { path: "/add-flight", icon: <Plus className="w-5 h-5" />, label: "Add Flight" },
    { path: "/import", icon: <Upload className="w-5 h-5" />, label: "Import CSV" },
  ];

  return (
    <div className="w-64 bg-white shadow-lg border-r border-slate-200 flex flex-col">
      {/* Logo */}
      <div className="p-6 border-b border-slate-200">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-aviation-blue rounded-lg flex items-center justify-center">
            <Plane className="w-6 h-6 text-white" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-slate-900">FlightTool</h1>
            <p className="text-sm text-slate-500">Flight Tracking</p>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 mt-8">
        <div className="px-6 py-2">
          <h3 className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Navigation</h3>
        </div>
        <div className="mt-2 space-y-1">
          {menuItems.map((item) => {
            const isActive = location === item.path;
            return (
              <button
                key={item.path}
                onClick={() => setLocation(item.path)}
                className={`group flex items-center px-6 py-3 text-sm font-medium w-full text-left transition-colors ${
                  isActive
                    ? "text-aviation-blue bg-blue-50 border-r-2 border-aviation-blue"
                    : "text-slate-600 hover:text-aviation-blue hover:bg-blue-50"
                }`}
              >
                <span className="mr-3">{item.icon}</span>
                {item.label}
              </button>
            );
          })}
        </div>

        <div className="px-6 py-2 mt-8">
          <h3 className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Account</h3>
        </div>
        <div className="mt-2 space-y-1">
          <button className="group flex items-center px-6 py-3 text-sm font-medium text-slate-600 hover:text-aviation-blue hover:bg-blue-50 w-full text-left">
            <User className="w-5 h-5 mr-3" />
            Profile
          </button>
          <button className="group flex items-center px-6 py-3 text-sm font-medium text-slate-600 hover:text-aviation-blue hover:bg-blue-50 w-full text-left">
            <Settings className="w-5 h-5 mr-3" />
            Settings
          </button>
        </div>
      </nav>

      {/* User Profile */}
      <div className="p-6 border-t border-slate-200 bg-white">
        <div className="flex items-center space-x-3">
          <img 
            src={user?.profileImageUrl || "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=150&h=150"} 
            alt="User Profile" 
            className="w-10 h-10 rounded-full object-cover" 
          />
          <div className="flex-1">
            <p className="text-sm font-medium text-slate-900">
              {user?.firstName && user?.lastName 
                ? `${user.firstName} ${user.lastName}`
                : user?.email || "User"}
            </p>
            <p className="text-xs text-slate-500">{user?.email}</p>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleLogout}
            className="text-slate-400 hover:text-slate-600"
          >
            <MoreVertical className="w-4 h-4" />
          </Button>
        </div>
      </div>
    </div>
  );
}
