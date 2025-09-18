import { useState } from "react";
import { Users, TrendingUp, Calendar, Filter, Download, Eye } from "lucide-react";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const networkStats = [
  {
    title: "Общая структура",
    stats: [
      { label: "Всего партнёров", value: "47", change: "+3" },
      { label: "Активных", value: "42", change: "+2" },
      { label: "Заморожено", value: "5", change: "+1" },
      { label: "Глубина структуры", value: "8 уровней", change: "" }
    ]
  },
  {
    title: "За этот месяц",
    stats: [
      { label: "Новые партнёры", value: "3", change: "+3" },
      { label: "Активации", value: "12", change: "+5" },
      { label: "Объём продаж", value: "$4,850", change: "+15%" },
      { label: "Комиссии", value: "$485", change: "+18%" }
    ]
  }
];

const recentActivity = [
  {
    type: "Новый партнёр",
    name: "Елена Петрова",
    time: "2 часа назад",
    details: "Зарегистрировалась по вашей ссылке",
    status: "active"
  },
  {
    type: "Активация",
    name: "Михаил Попов",
    time: "1 день назад", 
    details: "Выполнил месячную активацию $85",
    status: "success"
  },
  {
    type: "Заморозка",
    name: "Анна Козлова",
    time: "3 дня назад",
    details: "Аккаунт заморожен за неактивность",
    status: "warning"
  }
];

export default function Network() {
  const [searchQuery, setSearchQuery] = useState("");
  const [filterLevel, setFilterLevel] = useState("all");
  const [filterStatus, setFilterStatus] = useState("all");

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Моя сеть</h1>
          <p className="text-muted-foreground">
            Управление партнёрской структурой и анализ активности
          </p>
        </div>
        <div className="flex items-center space-x-2">
          <Button variant="outline">
            <Download className="h-4 w-4 mr-2" />
            Экспорт
          </Button>
          <Button className="hero-gradient border-0">
            <Users className="h-4 w-4 mr-2" />
            Пригласить партнёра
          </Button>
        </div>
      </div>

      {/* Statistics Cards */}
      <div className="grid gap-6 md:grid-cols-2">
        {networkStats.map((section, index) => (
          <Card key={index} className="financial-card">
            <CardHeader>
              <CardTitle>{section.title}</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-4">
                {section.stats.map((stat, statIndex) => (
                  <div key={statIndex} className="text-center">
                    <div className="text-2xl font-bold text-primary">{stat.value}</div>
                    <div className="text-sm text-muted-foreground">{stat.label}</div>
                    {stat.change && (
                      <div className="text-xs profit-indicator mt-1">
                        {stat.change}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Tabs for different views */}
      <Tabs defaultValue="tree" className="space-y-6">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="tree">Дерево структуры</TabsTrigger>
          <TabsTrigger value="list">Список партнёров</TabsTrigger>
          <TabsTrigger value="activity">Активность</TabsTrigger>
        </TabsList>

        <TabsContent value="tree" className="space-y-6">
          {/* Filters */}
          <Card className="financial-card">
            <CardContent className="p-4">
              <div className="flex flex-col md:flex-row gap-4">
                <div className="flex-1">
                  <Input
                    placeholder="Поиск по имени партнёра..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
                <Select value={filterLevel} onValueChange={setFilterLevel}>
                  <SelectTrigger className="w-48">
                    <SelectValue placeholder="Уровень" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все уровни</SelectItem>
                    <SelectItem value="1">1 уровень</SelectItem>
                    <SelectItem value="2">2 уровень</SelectItem>
                    <SelectItem value="3">3+ уровень</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={filterStatus} onValueChange={setFilterStatus}>
                  <SelectTrigger className="w-48">
                    <SelectValue placeholder="Статус" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все статусы</SelectItem>
                    <SelectItem value="active">Активные</SelectItem>
                    <SelectItem value="frozen">Заморожены</SelectItem>
                    <SelectItem value="inactive">Неактивные</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </CardContent>
          </Card>

          {/* Network Tree */}
          <NetworkTree />
        </TabsContent>

        <TabsContent value="list" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle>Список всех партнёров</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {[
                  { name: "Анна Смирнова", level: 2, status: "active", volume: "$1,250", team: 15 },
                  { name: "Михаил Попов", level: 2, status: "active", volume: "$1,850", team: 20 },
                  { name: "Петр Козлов", level: 3, status: "active", volume: "$680", team: 8 },
                  { name: "Елена Волкова", level: 3, status: "frozen", volume: "$0", team: 5 },
                ].map((partner, index) => (
                  <div key={index} className="flex items-center justify-between p-4 border border-border rounded-lg">
                    <div className="flex items-center space-x-4">
                      <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center">
                        <span className="text-primary font-medium text-sm">
                          {partner.name.split(' ').map(n => n[0]).join('')}
                        </span>
                      </div>
                      <div>
                        <p className="font-medium">{partner.name}</p>
                        <p className="text-sm text-muted-foreground">Уровень {partner.level}</p>
                      </div>
                    </div>
                    <div className="flex items-center space-x-4">
                      <Badge className={
                        partner.status === "active" ? "profit-indicator" :
                        partner.status === "frozen" ? "pending-indicator" : "frozen-indicator"
                      }>
                        {partner.status === "active" ? "Активен" :
                         partner.status === "frozen" ? "Заморожен" : "Неактивен"}
                      </Badge>
                      <div className="text-right">
                        <p className="font-medium">{partner.volume}</p>
                        <p className="text-sm text-muted-foreground">Команда: {partner.team}</p>
                      </div>
                      <Button variant="outline" size="sm">
                        <Eye className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="activity" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle>Последняя активность в сети</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {recentActivity.map((activity, index) => (
                  <div key={index} className="flex items-center space-x-4 p-4 border border-border rounded-lg">
                    <div className={`w-3 h-3 rounded-full ${
                      activity.status === "active" ? "bg-primary" :
                      activity.status === "success" ? "bg-success" :
                      "bg-warning"
                    }`}></div>
                    <div className="flex-1">
                      <div className="flex items-center space-x-2 mb-1">
                        <span className="font-medium">{activity.type}</span>
                        <span className="text-muted-foreground">•</span>
                        <span className="font-medium">{activity.name}</span>
                      </div>
                      <p className="text-sm text-muted-foreground">{activity.details}</p>
                    </div>
                    <div className="text-sm text-muted-foreground">
                      {activity.time}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Referral Link Card */}
      <Card className="border-primary/20 bg-primary/5">
        <CardHeader>
          <CardTitle className="text-primary">Ваша реферальная ссылка</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center space-x-2">
            <code className="flex-1 bg-background border border-border px-3 py-2 rounded text-sm">
              https://mlm-platform.com/ref/12345
            </code>
            <Button variant="outline">Копировать</Button>
            <Button className="hero-gradient border-0">Поделиться</Button>
          </div>
          <p className="text-sm text-muted-foreground mt-3">
            Поделитесь этой ссылкой для приглашения новых партнёров в вашу команду
          </p>
        </CardContent>
      </Card>
    </div>
  );
}