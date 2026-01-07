import { TrendingUp, TrendingDown, Users, DollarSign, Snowflake } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useBalance } from "@/hooks/useBalance";
import { useNetworkStats } from "@/hooks/useNetworkStats";
import { formatKZT } from "@/utils/formatMoney";

export function DashboardStats() {
  const { data: balance, isLoading: balanceLoading } = useBalance();
  const { data: networkStats, isLoading: statsLoading } = useNetworkStats();

  const stats = [
    {
      title: "Доступный баланс",
      value: balanceLoading ? null : formatKZT(balance?.available_kzt || 0, 'KZT'),
      change: "+0%",
      trend: "up" as const,
      icon: DollarSign,
      description: "Доступно для вывода"
    },
    {
      title: "Активные партнёры",
      value: statsLoading ? null : String(networkStats?.active_partners || 0),
      change: statsLoading ? null : `+${networkStats?.new_this_month || 0}`,
      trend: "up" as const,
      icon: Users,
      description: "Новых в этом месяце"
    },
    {
      title: "Замороженные средства",
      value: balanceLoading ? null : formatKZT(balance?.frozen_kzt || 0, 'KZT'),
      change: "-0%",
      trend: "down" as const,
      icon: Snowflake,
      description: "Ожидают разморозки (14 дней)"
    },
  ];

  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
      {stats.map((stat) => {
        const Icon = stat.icon;
        const isUp = stat.trend === "up";
        const isLoading = stat.value === null;
        
        return (
          <Card key={stat.title} className="financial-card">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {stat.title}
              </CardTitle>
              <Icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              {isLoading ? (
                <>
                  <Skeleton className="h-8 w-24 mb-2" />
                  <Skeleton className="h-5 w-16 mb-2" />
                  <Skeleton className="h-4 w-32" />
                </>
              ) : (
                <>
                  <div className="text-2xl font-bold">{stat.value}</div>
                  {stat.change && (
                    <div className="flex items-center space-x-2 mt-2">
                      <Badge 
                        variant="secondary" 
                        className={
                          isUp ? "profit-indicator" : "loss-indicator"
                        }
                      >
                        {isUp ? (
                          <TrendingUp className="h-3 w-3 mr-1" />
                        ) : (
                          <TrendingDown className="h-3 w-3 mr-1" />
                        )}
                        {stat.change}
                      </Badge>
                    </div>
                  )}
                  <p className="text-xs text-muted-foreground mt-2">
                    {stat.description}
                  </p>
                </>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}