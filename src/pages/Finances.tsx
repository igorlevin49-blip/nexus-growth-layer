import { useState } from "react";
import { DollarSign, TrendingUp, TrendingDown, Calendar, Download, CreditCard, Wallet } from "lucide-react";
import { useBalance } from "@/hooks/useBalance";
import { useTransactions } from "@/hooks/useTransactions";
import { useCommissionStructure } from "@/hooks/useCommissionStructure";
import { formatCents } from "@/utils/formatMoney";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { WithdrawalDialog } from "@/components/Finances/WithdrawalDialog";
import { PaymentMethodsDialog } from "@/components/Finances/PaymentMethodsDialog";
import { AutoWithdrawDialog } from "@/components/Finances/AutoWithdrawDialog";

export default function Finances() {
  const [period, setPeriod] = useState("month");
  const [transactionFilter, setTransactionFilter] = useState("all");
  const [withdrawalOpen, setWithdrawalOpen] = useState(false);
  const [paymentMethodsOpen, setPaymentMethodsOpen] = useState(false);
  const [autoWithdrawOpen, setAutoWithdrawOpen] = useState(false);
  
  // Get real data from hooks
  const { data: balance, isLoading: balanceLoading } = useBalance();
  const { data: transactions, isLoading: transactionsLoading } = useTransactions({
    type: transactionFilter === 'all' ? undefined : 
          transactionFilter === 'income' ? ['commission', 'bonus'] :
          transactionFilter === 'expense' ? ['withdrawal', 'purchase'] :
          undefined
  });
  const { data: commissionLevels, isLoading: commissionsLoading } = useCommissionStructure({ structureType: 'primary' });
  
  // Calculate period dates
  const getDateRange = () => {
    const now = new Date();
    const start = new Date();
    
    switch (period) {
      case 'week':
        start.setDate(now.getDate() - 7);
        break;
      case 'month':
        start.setMonth(now.getMonth() - 1);
        break;
      case 'quarter':
        start.setMonth(now.getMonth() - 3);
        break;
      case 'year':
        start.setFullYear(now.getFullYear() - 1);
        break;
    }
    
    return { start, end: now };
  };

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
        {[
          {
            title: "Доступный баланс",
            amount: balance ? formatCents(balance.available_cents) : "$0.00",
            description: "Доступно для вывода",
            loading: balanceLoading
          },
          {
            title: "Заморожено",
            amount: balance ? formatCents(balance.frozen_cents) : "$0.00",
            description: "Разморозка через 7 дней",
            loading: balanceLoading
          },
          {
            title: "В ожидании",
            amount: balance ? formatCents(balance.pending_cents) : "$0.00",
            description: "Обработка платежей",
            loading: balanceLoading
          },
          {
            title: "Выведено",
            amount: balance ? formatCents(balance.withdrawn_cents) : "$0.00",
            description: "Всего выведено",
            loading: balanceLoading
          }
        ].map((item, index) => (
          <Card key={index} className="financial-card">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {item.title}
              </CardTitle>
              <DollarSign className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{item.amount}</div>
              <p className="text-xs text-muted-foreground mt-2">
                {item.description}
              </p>
            </CardContent>
          </Card>
        ))}
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
                <p className="text-sm text-muted-foreground">
                  Доступно: {balance ? formatCents(balance.available_cents) : "$0.00"}
                </p>
              </div>
              <Button className="hero-gradient border-0" onClick={() => setWithdrawalOpen(true)}>
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
              <Button variant="outline" onClick={() => setPaymentMethodsOpen(true)}>
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
              <Button variant="outline" onClick={() => setAutoWithdrawOpen(true)}>
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
                {transactionsLoading ? (
                  <p className="text-center text-muted-foreground">Загрузка...</p>
                ) : !transactions || transactions.length === 0 ? (
                  <p className="text-center text-muted-foreground">Нет транзакций</p>
                ) : (
                  transactions.map((transaction) => {
                    const typeLabels: Record<string, string> = {
                      commission: 'Комиссия',
                      bonus: 'Бонус',
                      withdrawal: 'Вывод',
                      purchase: 'Покупка',
                      adjustment: 'Корректировка'
                    };
                    
                    return (
                      <div key={transaction.id} className="flex items-center justify-between p-4 border border-border rounded-lg">
                        <div className="flex-1">
                          <div className="flex items-center space-x-3 mb-2">
                            <span className="font-medium">{typeLabels[transaction.type] || transaction.type}</span>
                            {transaction.level && (
                              <Badge variant="outline" className="text-xs">
                                {transaction.level === 1 ? 'Прямой' : `${transaction.level}-й уровень`}
                              </Badge>
                            )}
                            {getStatusBadge(transaction.status)}
                          </div>
                          <p className="text-sm text-muted-foreground mb-1">
                            {transaction.payload?.description || `${typeLabels[transaction.type]} ${formatCents(transaction.amount_cents)}`}
                          </p>
                          <div className="flex items-center space-x-4 text-xs text-muted-foreground">
                            <span>ID: {transaction.id.substring(0, 8)}</span>
                            <span>{new Date(transaction.created_at).toLocaleString('ru-RU')}</span>
                          </div>
                        </div>
                        <div className={`text-lg font-bold ${
                          ['commission', 'bonus'].includes(transaction.type) ? "text-success" : "text-muted-foreground"
                        }`}>
                          {['commission', 'bonus'].includes(transaction.type) ? '+' : '-'}
                          {formatCents(transaction.amount_cents)}
                        </div>
                      </div>
                    );
                  })
                )}
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
                {commissionsLoading ? (
                  <p className="text-center text-muted-foreground">Загрузка...</p>
                ) : !commissionLevels || commissionLevels.length === 0 ? (
                  <p className="text-center text-muted-foreground">Нет данных о комиссиях</p>
                ) : (
                  commissionLevels.map((level) => (
                    <div key={level.level} className="flex items-center justify-between p-4 border border-border rounded-lg">
                      <div className="flex items-center space-x-4">
                        <div className="w-8 h-8 bg-primary/10 rounded-full flex items-center justify-center">
                          <span className="text-primary font-bold text-sm">{level.level}</span>
                        </div>
                        <div>
                          <p className="font-medium">{level.description || `Уровень ${level.level}`}</p>
                          <p className="text-sm text-muted-foreground">
                            Комиссия: {level.percent}%
                          </p>
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="font-medium text-success">{formatCents(level.earned || 0)}</p>
                        <p className="text-sm text-muted-foreground">
                          из оборота {formatCents(level.volume || 0)}
                        </p>
                      </div>
                    </div>
                  ))
                )}
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

      <WithdrawalDialog open={withdrawalOpen} onOpenChange={setWithdrawalOpen} />
      <PaymentMethodsDialog open={paymentMethodsOpen} onOpenChange={setPaymentMethodsOpen} />
      <AutoWithdrawDialog open={autoWithdrawOpen} onOpenChange={setAutoWithdrawOpen} />
    </div>
  );
}