import { Calendar, Target, Users, Wallet } from "lucide-react";
import { DashboardStats } from "@/components/Dashboard/DashboardStats";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { ActivationProgress } from "@/components/Dashboard/ActivationProgress";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
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

      {/* Quick Actions & Activation Progress */}
      <div className="grid gap-6 md:grid-cols-2">
        <Card className="financial-card">
          <CardHeader>
            <CardTitle className="flex items-center space-x-2">
              <Target className="h-5 w-5" />
              <span>Быстрые действия</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
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

        <ActivationProgress />
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