import { Calendar, Target, Users, Wallet } from "lucide-react";
import { DashboardStats } from "@/components/Dashboard/DashboardStats";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";

export default function Dashboard() {
  return (
    <div className="p-6 space-y-6">
      {/* Welcome Section */}
      <div className="hero-gradient rounded-lg p-6 text-white">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold mb-2">Добро пожаловать, Иван!</h1>
            <p className="text-white/80 mb-4">
              Ваша подписка активна. Продолжайте развивать свою сеть и достигать новых целей.
            </p>
            <div className="flex items-center space-x-4 text-sm">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-white rounded-full"></div>
                <span>Партнёр уровня Gold</span>
              </div>
              <div className="flex items-center space-x-2">
                <Calendar className="h-4 w-4" />
                <span>Активен с 15.01.2024</span>
              </div>
            </div>
          </div>
          <div className="hidden md:block text-right">
            <div className="text-sm text-white/80 mb-1">Ваш ID</div>
            <div className="text-2xl font-bold">#12345</div>
          </div>
        </div>
      </div>

      {/* Stats Grid */}
      <DashboardStats />

      {/* Quick Actions & Alerts */}
      <div className="grid gap-6 md:grid-cols-2">
        <Card className="financial-card">
          <CardHeader>
            <CardTitle className="flex items-center space-x-2">
              <Target className="h-5 w-5" />
              <span>Быстрые действия</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button className="w-full hero-gradient border-0" size="lg">
              <Wallet className="h-4 w-4 mr-2" />
              Продлить подписку
            </Button>
            <Button variant="outline" className="w-full" size="lg">
              <Users className="h-4 w-4 mr-2" />
              Пригласить партнёра
            </Button>
            <div className="pt-3 border-t border-border">
              <p className="text-sm text-muted-foreground mb-2">
                Ваша реферальная ссылка:
              </p>
              <div className="flex items-center space-x-2">
                <code className="flex-1 bg-muted px-2 py-1 rounded text-xs">
                  https://mlm-platform.com/ref/12345
                </code>
                <Button variant="outline" size="sm">
                  Копировать
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="financial-card">
          <CardHeader>
            <CardTitle>Месячные цели</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <div className="flex justify-between text-sm mb-2">
                <span>Активация ($100)</span>
                <span>$85.50</span>
              </div>
              <Progress value={85.5} className="mb-1" />
              <p className="text-xs text-muted-foreground">
                Осталось $14.50 до завершения
              </p>
            </div>

            <div>
              <div className="flex justify-between text-sm mb-2">
                <span>Новые партнёры (5)</span>
                <span>3</span>
              </div>
              <Progress value={60} className="mb-1" />
              <p className="text-xs text-muted-foreground">
                Пригласите ещё 2 партнёра
              </p>
            </div>

            <div className="pt-3 border-t border-border">
              <Badge className="profit-indicator mb-2">
                🎯 Цель месяца: 85% выполнено
              </Badge>
              <p className="text-xs text-muted-foreground">
                При достижении целей вы получите бонус $150
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Network Tree */}
      <NetworkTree />

      {/* Recent Activity */}
      <Card className="financial-card">
        <CardHeader>
          <CardTitle>Последние операции</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {[
              {
                type: "Начисление",
                description: "Комиссия с покупки партнёра Анна Смирнова",
                amount: "+$45.00",
                date: "2 часа назад",
                positive: true
              },
              {
                type: "Покупка",
                description: "Активационный товар Premium Pack",
                amount: "-$85.50",
                date: "1 день назад",
                positive: false
              },
              {
                type: "Начисление",
                description: "Бонус за приглашение нового партнёра",
                amount: "+$25.00",
                date: "2 дня назад",
                positive: true
              }
            ].map((transaction, index) => (
              <div key={index} className="flex items-center justify-between py-3 border-b border-border last:border-b-0">
                <div>
                  <p className="font-medium">{transaction.type}</p>
                  <p className="text-sm text-muted-foreground">{transaction.description}</p>
                  <p className="text-xs text-muted-foreground">{transaction.date}</p>
                </div>
                <div className={`font-bold ${
                  transaction.positive ? "text-success" : "text-muted-foreground"
                }`}>
                  {transaction.amount}
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}