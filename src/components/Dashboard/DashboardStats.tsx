import { TrendingUp, TrendingDown, Users, DollarSign, Calendar, Snowflake } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";

const stats = [
  {
    title: "Общий баланс",
    value: "$2,847.50",
    change: "+12.5%",
    trend: "up" as const,
    icon: DollarSign,
    description: "За последние 30 дней"
  },
  {
    title: "Активные партнёры",
    value: "47",
    change: "+3",
    trend: "up" as const,
    icon: Users,
    description: "Новых в этом месяце"
  },
  {
    title: "Замороженные средства",
    value: "$450.00",
    change: "-5.2%",
    trend: "down" as const,
    icon: Snowflake,
    description: "Ожидают разморозки"
  },
  {
    title: "Месячная активация",
    value: "$85.50",
    change: "85.5%",
    trend: "up" as const,
    icon: Calendar,
    description: "из $100 требуемых"
  },
];

export function DashboardStats() {
  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
      {stats.map((stat) => {
        const Icon = stat.icon;
        const isUp = stat.trend === "up";
        
        return (
          <Card key={stat.title} className="financial-card">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {stat.title}
              </CardTitle>
              <Icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stat.value}</div>
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
              <p className="text-xs text-muted-foreground mt-2">
                {stat.description}
              </p>
              {stat.title === "Месячная активация" && (
                <Progress value={85.5} className="mt-3" />
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}