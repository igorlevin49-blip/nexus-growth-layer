import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { DollarSign, TrendingUp, Users, ShoppingCart } from "lucide-react";

export default function AdminReports() {
  const stats = [
    {
      title: "Общий доход",
      value: "$45,231.89",
      change: "+20.1% от прошлого месяца",
      icon: DollarSign,
    },
    {
      title: "Активные пользователи",
      value: "2,350",
      change: "+180 новых",
      icon: Users,
    },
    {
      title: "Продажи",
      value: "12,234",
      change: "+19% от прошлого месяца",
      icon: ShoppingCart,
    },
    {
      title: "Средний чек",
      value: "$189",
      change: "+5.2% от прошлого месяца",
      icon: TrendingUp,
    },
  ];

  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold mb-6">Финансовые отчеты</h1>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-8">
        {stats.map((stat) => (
          <Card key={stat.title}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">
                {stat.title}
              </CardTitle>
              <stat.icon className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stat.value}</div>
              <p className="text-xs text-muted-foreground">
                {stat.change}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Детальные отчеты</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">
            Здесь будут графики и детальная аналитика
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
