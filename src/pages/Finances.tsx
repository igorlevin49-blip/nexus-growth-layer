import { useState } from "react";
import { DollarSign, TrendingUp, TrendingDown, Calendar, Download, CreditCard, Wallet } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const balanceData = [
  {
    title: "Доступный баланс",
    amount: "$2,847.50",
    change: "+$485.00",
    trend: "up" as const,
    description: "Доступно для вывода"
  },
  {
    title: "Заморожено",
    amount: "$450.00",
    change: "-$50.00",
    trend: "down" as const,
    description: "Разморозка через 7 дней"
  },
  {
    title: "В ожидании",
    amount: "$125.00",
    change: "+$125.00",
    trend: "up" as const,
    description: "Обработка платежей"
  },
  {
    title: "Выведено",
    amount: "$3,250.00",
    change: "+$250.00",
    trend: "up" as const,
    description: "Всего выведено"
  }
];

const transactions = [
  {
    id: "TXN001",
    type: "Комиссия",
    description: "Комиссия с покупки партнёра Анна Смирнова - Premium Pack",
    amount: "+$85.50",
    status: "completed",
    date: "2024-01-15 14:30",
    level: "2-й уровень",
    positive: true
  },
  {
    id: "TXN002",
    type: "Бонус",
    description: "Бонус за приглашение нового партнёра Михаил Попов",
    amount: "+$25.00",
    status: "completed",
    date: "2024-01-14 09:15",
    level: "Прямой",
    positive: true
  },
  {
    id: "TXN003",
    type: "Вывод",
    description: "Вывод средств на карту ****1234",
    amount: "-$500.00",
    status: "processing",
    date: "2024-01-13 16:45",
    level: "",
    positive: false
  },
  {
    id: "TXN004",
    type: "Покупка",
    description: "Активационный товар Energy Boost Formula",
    amount: "-$45.00",
    status: "completed",
    date: "2024-01-12 11:20",
    level: "",
    positive: false
  },
  {
    id: "TXN005",
    type: "Комиссия",
    description: "Командная комиссия за объёмы 3-го уровня",
    amount: "+$125.50",
    status: "completed",
    date: "2024-01-10 18:00",
    level: "3-й уровень",
    positive: true
  }
];

const commissionStructure = [
  { level: 1, percentage: 25, description: "Прямые рефералы", volume: "$2,450", earned: "$612.50" },
  { level: 2, percentage: 15, description: "Второй уровень", volume: "$1,850", earned: "$277.50" },
  { level: 3, percentage: 10, description: "Третий уровень", volume: "$980", earned: "$98.00" },
  { level: 4, percentage: 8, description: "Четвёртый уровень", volume: "$650", earned: "$52.00" },
  { level: 5, percentage: 5, description: "Пятый уровень", volume: "$420", earned: "$21.00" }
];

export default function Finances() {
  const [period, setPeriod] = useState("month");
  const [transactionFilter, setTransactionFilter] = useState("all");

  const getStatusBadge = (status: string) => {
    switch (status) {
      case "completed":
        return <Badge className="profit-indicator">Завершено</Badge>;
      case "processing":
        return <Badge className="pending-indicator">Обработка</Badge>;
      case "failed":
        return <Badge className="loss-indicator">Ошибка</Badge>;
      default:
        return <Badge className="frozen-indicator">Неизвестно</Badge>;
    }
  };

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Финансы</h1>
          <p className="text-muted-foreground">
            Управление балансом, комиссиями и выводом средств
          </p>
        </div>
        <div className="flex items-center space-x-2">
          <Select value={period} onValueChange={setPeriod}>
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="week">За неделю</SelectItem>
              <SelectItem value="month">За месяц</SelectItem>
              <SelectItem value="quarter">За квартал</SelectItem>
              <SelectItem value="year">За год</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline">
            <Download className="h-4 w-4 mr-2" />
            Отчёт
          </Button>
        </div>
      </div>

      {/* Balance Cards */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {balanceData.map((balance, index) => {
          const Icon = DollarSign;
          const isUp = balance.trend === "up";
          
          return (
            <Card key={index} className="financial-card">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">
                  {balance.title}
                </CardTitle>
                <Icon className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{balance.amount}</div>
                <div className="flex items-center space-x-2 mt-2">
                  <Badge 
                    variant="secondary" 
                    className={isUp ? "profit-indicator" : "loss-indicator"}
                  >
                    {isUp ? (
                      <TrendingUp className="h-3 w-3 mr-1" />
                    ) : (
                      <TrendingDown className="h-3 w-3 mr-1" />
                    )}
                    {balance.change}
                  </Badge>
                </div>
                <p className="text-xs text-muted-foreground mt-2">
                  {balance.description}
                </p>
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* Quick Actions */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card className="financial-card">
          <CardContent className="p-6">
            <div className="flex items-center space-x-4">
              <div className="w-12 h-12 bg-success/10 rounded-lg flex items-center justify-center">
                <Wallet className="h-6 w-6 text-success" />
              </div>
              <div className="flex-1">
                <h3 className="font-semibold">Вывести средства</h3>
                <p className="text-sm text-muted-foreground">Доступно: $2,847.50</p>
              </div>
              <Button className="hero-gradient border-0">
                Вывести
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card className="financial-card">
          <CardContent className="p-6">
            <div className="flex items-center space-x-4">
              <div className="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center">
                <CreditCard className="h-6 w-6 text-primary" />
              </div>
              <div className="flex-1">
                <h3 className="font-semibold">Способы оплаты</h3>
                <p className="text-sm text-muted-foreground">Управление картами</p>
              </div>
              <Button variant="outline">
                Настроить
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card className="financial-card">
          <CardContent className="p-6">
            <div className="flex items-center space-x-4">
              <div className="w-12 h-12 bg-warning/10 rounded-lg flex items-center justify-center">
                <Calendar className="h-6 w-6 text-warning" />
              </div>
              <div className="flex-1">
                <h3 className="font-semibold">Автовывод</h3>
                <p className="text-sm text-muted-foreground">Не настроен</p>
              </div>
              <Button variant="outline">
                Включить
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs defaultValue="transactions" className="space-y-6">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="transactions">История операций</TabsTrigger>
          <TabsTrigger value="commissions">Комиссионная структура</TabsTrigger>
          <TabsTrigger value="analytics">Аналитика</TabsTrigger>
        </TabsList>

        <TabsContent value="transactions" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle>История транзакций</CardTitle>
                <Select value={transactionFilter} onValueChange={setTransactionFilter}>
                  <SelectTrigger className="w-48">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все операции</SelectItem>
                    <SelectItem value="income">Доходы</SelectItem>
                    <SelectItem value="expense">Расходы</SelectItem>
                    <SelectItem value="pending">В обработке</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {transactions.map((transaction) => (
                  <div key={transaction.id} className="flex items-center justify-between p-4 border border-border rounded-lg">
                    <div className="flex-1">
                      <div className="flex items-center space-x-3 mb-2">
                        <span className="font-medium">{transaction.type}</span>
                        {transaction.level && (
                          <Badge variant="outline" className="text-xs">
                            {transaction.level}
                          </Badge>
                        )}
                        {getStatusBadge(transaction.status)}
                      </div>
                      <p className="text-sm text-muted-foreground mb-1">
                        {transaction.description}
                      </p>
                      <div className="flex items-center space-x-4 text-xs text-muted-foreground">
                        <span>ID: {transaction.id}</span>
                        <span>{transaction.date}</span>
                      </div>
                    </div>
                    <div className={`text-lg font-bold ${
                      transaction.positive ? "text-success" : "text-muted-foreground"
                    }`}>
                      {transaction.amount}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="commissions" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle>Комиссионная структура</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {commissionStructure.map((level) => (
                  <div key={level.level} className="flex items-center justify-between p-4 border border-border rounded-lg">
                    <div className="flex items-center space-x-4">
                      <div className="w-8 h-8 bg-primary/10 rounded-full flex items-center justify-center">
                        <span className="text-primary font-bold text-sm">{level.level}</span>
                      </div>
                      <div>
                        <p className="font-medium">{level.description}</p>
                        <p className="text-sm text-muted-foreground">
                          Комиссия: {level.percentage}%
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="font-medium text-success">{level.earned}</p>
                      <p className="text-sm text-muted-foreground">
                        из оборота {level.volume}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="analytics" className="space-y-6">
          <div className="grid gap-6 md:grid-cols-2">
            <Card className="financial-card">
              <CardHeader>
                <CardTitle>Доходы по месяцам</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {[
                    { month: "Январь", amount: "$1,250", change: "+15%" },
                    { month: "Декабрь", amount: "$1,180", change: "+8%" },
                    { month: "Ноябрь", amount: "$1,090", change: "+12%" },
                    { month: "Октябрь", amount: "$975", change: "+5%" }
                  ].map((data, index) => (
                    <div key={index} className="flex items-center justify-between">
                      <span className="text-sm">{data.month}</span>
                      <div className="flex items-center space-x-2">
                        <span className="font-medium">{data.amount}</span>
                        <Badge className="profit-indicator text-xs">
                          {data.change}
                        </Badge>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            <Card className="financial-card">
              <CardHeader>
                <CardTitle>Источники дохода</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {[
                    { source: "Прямые комиссии", amount: "$612.50", percent: "48%" },
                    { source: "Командные бонусы", amount: "$485.00", percent: "38%" },
                    { source: "Активационные", amount: "$180.00", percent: "14%" }
                  ].map((data, index) => (
                    <div key={index} className="space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="text-sm">{data.source}</span>
                        <span className="font-medium">{data.amount}</span>
                      </div>
                      <div className="w-full bg-muted rounded-full h-2">
                        <div 
                          className="bg-primary h-2 rounded-full" 
                          style={{ width: data.percent }}
                        ></div>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}