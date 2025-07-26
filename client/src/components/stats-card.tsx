import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

interface StatsCardProps {
  title: string;
  value: number | string;
  suffix?: string;
  icon: React.ReactNode;
  trend?: string;
  trendLabel?: string;
  loading?: boolean;
}

export default function StatsCard({ 
  title, 
  value, 
  suffix, 
  icon, 
  trend, 
  trendLabel, 
  loading 
}: StatsCardProps) {
  if (loading) {
    return (
      <Card>
        <CardContent className="p-6">
          <div className="flex items-center justify-between">
            <div className="space-y-2">
              <Skeleton className="h-4 w-20" />
              <Skeleton className="h-8 w-16" />
            </div>
            <Skeleton className="w-12 h-12 rounded-lg" />
          </div>
          <div className="mt-4">
            <Skeleton className="h-4 w-24" />
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-6">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-medium text-slate-600">{title}</p>
            <div className="flex items-baseline space-x-1">
              <p className="text-3xl font-bold text-slate-900">
                {typeof value === 'number' ? value.toLocaleString() : value}
              </p>
              {suffix && <p className="text-xs text-slate-500">{suffix}</p>}
            </div>
          </div>
          <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
            {icon}
          </div>
        </div>
        {(trend || trendLabel) && (
          <div className="mt-4 flex items-center">
            {trend && (
              <span className="text-green-500 text-sm font-medium">{trend}</span>
            )}
            {trendLabel && (
              <span className="text-slate-500 text-sm ml-1">{trendLabel}</span>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
