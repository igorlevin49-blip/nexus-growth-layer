import { useState } from "react";
import { DollarSign, Calendar, Download, CreditCard, Wallet } from "lucide-react";
import { useBalance } from "@/hooks/useBalance";
import { useTransactions } from "@/hooks/useTransactions";
import { useCommissionStructure } from "@/hooks/useCommissionStructure";
import { useProfile } from "@/hooks/useProfile";
import { formatKZT } from "@/utils/formatMoney";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { WithdrawalDialog } from "@/components/Finances/WithdrawalDialog";
import { PaymentMethodsDialog } from "@/components/Finances/PaymentMethodsDialog";
import { AutoWithdrawDialog } from "@/components/Finances/AutoWithdrawDialog";
import { SubscriptionStructure } from "@/components/Finances/SubscriptionStructure";
import { ProductStructure } from "@/components/Finances/ProductStructure";
import { WithdrawalsHistory } from "@/components/Finances/WithdrawalsHistory";

export default function Finances() {
  const [period, setPeriod] = useState("month");
  const [transactionFilter, setTransactionFilter] = useState("all");
  const [withdrawalOpen, setWithdrawalOpen] = useState(false);
  const [paymentMethodsOpen, setPaymentMethodsOpen] = useState(false);
  const [autoWithdrawOpen, setAutoWithdrawOpen] = useState(false);
  
  // Get real data from hooks
  const { data: balance, isLoading: balanceLoading } = useBalance();
  const { data: profile } = useProfile();
  const { data: transactions, isLoading: transactionsLoading } = useTransactions({
    type: transactionFilter === 'all' ? undefined : 
          transactionFilter === 'income' ? ['commission', 'bonus'] :
          transactionFilter === 'expense' ? ['withdrawal', 'purchase'] :
          undefined
  });
  
  // Структура 1 (Абонентская - 5 уровней)
  const { data: structure1Levels, isLoading: structure1Loading } = useCommissionStructure({ structureType: 1 });
  
  // Структура 2 (Товарная - 10 уровней)
  const { data: structure2Levels, isLoading: structure2Loading } = useCommissionStructure({ structureType: 2 });
  
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

  // Analytics calculations
  const nowDate = new Date();
  // Fetch last 4 months of income transactions for analytics
  const analyticsStart = new Date(nowDate.getFullYear(), nowDate.getMonth() - 3, 1);
  const { data: analyticsTxs } = useTransactions({
    type: ['commission', 'bonus'],
    limit: 1000,
  });

  const monthNames = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь'];
  const monthlyAnalytics = Array.from({ length: 4 }).map((_, idx) => {
    const d = new Date(nowDate.getFullYear(), nowDate.getMonth() - (3 - idx), 1);
    const startM = new Date(d.getFullYear(), d.getMonth(), 1);
    const endM = new Date(d.getFullYear(), d.getMonth() + 1, 1);
    const amountKzt = (analyticsTxs || [])
      .filter(t => new Date(t.created_at) >= startM && new Date(t.created_at) < endM)
      .filter(t => (t.type === 'commission' || t.type === 'bonus') && t.status === 'completed')
      .reduce((sum, t) => sum + (t.amount_kzt || 0), 0);
    return { month: monthNames[d.getMonth()], amountCents: amountKzt };
  });

  const monthlyWithChange = monthlyAnalytics.map((m, i) => {
    const prev = i > 0 ? monthlyAnalytics[i - 1].amountCents : 0;
    const change = prev > 0 ? Math.round(((m.amountCents - prev) / prev) * 100) : 0;
    return { ...m, change };
  });

  // Sources for selected period
  const { start, end } = getDateRange();
  const periodTxs = (analyticsTxs || []).filter(t => {
    const d = new Date(t.created_at);
    return d >= start && d <= end && t.status === 'completed';
  });
  const directCents = periodTxs
    .filter(t => t.type === 'commission' && (t.level === 1))
    .reduce((s, t) => s + (t.amount_kzt || 0), 0);
  const teamBonusCents = periodTxs
    .filter(t => t.type === 'bonus' || (t.type === 'commission' && ((t.level ?? 0) > 1)))
    .reduce((s, t) => s + (t.amount_kzt || 0), 0);
  const activationCents = periodTxs
    .filter(t => t.type === 'commission' && (
      (t.payload?.type && String(t.payload.type).toLowerCase().includes('activation')) ||
      t.payload?.structure === 'secondary' ||
      t.payload?.has_activation === true
    ))
    .reduce((s, t) => s + (t.amount_kzt || 0), 0);
  const totalSources = directCents + teamBonusCents + activationCents;

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold">Финансы</h1>
          <p className="text-muted-foreground">
            Управление балансом, комиссиями и выводом средств
          </p>
        </div>
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
          <Select value={period} onValueChange={setPeriod}>
            <SelectTrigger className="w-full sm:w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="week">За неделю</SelectItem>
              <SelectItem value="month">За месяц</SelectItem>
              <SelectItem value="quarter">За квартал</SelectItem>
              <SelectItem value="year">За год</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" className="w-full sm:w-auto">
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
            amount: balance ? formatKZT(balance.available_kzt) : "0 ₸",
            description: "Доступно для вывода",
            loading: balanceLoading
          },
          {
            title: "Заморожено",
            amount: balance ? formatKZT(balance.frozen_kzt) : "0 ₸",
            description: "Разморозка через 7 дней",
            loading: balanceLoading
          },
          {
            title: "В ожидании",
            amount: balance ? formatKZT(balance.pending_kzt) : "0 ₸",
            description: "Обработка платежей",
            loading: balanceLoading
          },
          {
            title: "Выведено",
            amount: balance ? formatKZT(balance.withdrawn_kzt) : "0 ₸",
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
          <CardContent className="p-4 sm:p-6">
            <div className="flex flex-col sm:flex-row sm:items-center gap-4">
              <div className="flex items-center gap-4 flex-1">
                <div className="w-12 h-12 bg-success/10 rounded-lg flex items-center justify-center shrink-0">
                  <Wallet className="h-6 w-6 text-success" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold">Вывести средства</h3>
                  <p className="text-sm text-muted-foreground">
                    Доступно: {balance ? formatKZT(balance.available_kzt) : "0 ₸"}
                  </p>
                </div>
              </div>
              <Button className="hero-gradient border-0 w-full sm:w-auto" onClick={() => setWithdrawalOpen(true)}>
                Вывести
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card className="financial-card">
          <CardContent className="p-4 sm:p-6">
            <div className="flex flex-col sm:flex-row sm:items-center gap-4">
              <div className="flex items-center gap-4 flex-1">
                <div className="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center shrink-0">
                  <CreditCard className="h-6 w-6 text-primary" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold">Способы оплаты</h3>
                  <p className="text-sm text-muted-foreground">Управление картами</p>
                </div>
              </div>
              <Button variant="outline" className="w-full sm:w-auto" onClick={() => setPaymentMethodsOpen(true)}>
                Настроить
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card className="financial-card">
          <CardContent className="p-4 sm:p-6">
            <div className="flex flex-col sm:flex-row sm:items-center gap-4">
              <div className="flex items-center gap-4 flex-1">
                <div className="w-12 h-12 bg-warning/10 rounded-lg flex items-center justify-center shrink-0">
                  <Calendar className="h-6 w-6 text-warning" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold">Автовывод</h3>
                  <p className="text-sm text-muted-foreground">Не настроен</p>
                </div>
              </div>
              <Button variant="outline" className="w-full sm:w-auto" onClick={() => setAutoWithdrawOpen(true)}>
                Включить
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Tabs */}
      <Tabs defaultValue="transactions" className="space-y-6">
        <TabsList className="grid w-full grid-cols-5 h-auto">
          <TabsTrigger value="transactions" className="text-xs sm:text-sm px-2 py-2">
            <span className="hidden sm:inline">История</span>
            <span className="sm:hidden">История</span>
          </TabsTrigger>
          <TabsTrigger value="withdrawals" className="text-xs sm:text-sm px-2 py-2">
            <span className="hidden sm:inline">Выплаты</span>
            <span className="sm:hidden">Выплаты</span>
          </TabsTrigger>
          <TabsTrigger value="structure1" className="text-xs sm:text-sm px-2 py-2">
            <span className="hidden sm:inline">Абонентская</span>
            <span className="sm:hidden">С1</span>
          </TabsTrigger>
          <TabsTrigger value="structure2" className="text-xs sm:text-sm px-2 py-2">
            <span className="hidden sm:inline">Товарная</span>
            <span className="sm:hidden">С2</span>
          </TabsTrigger>
          <TabsTrigger value="analytics" className="text-xs sm:text-sm px-2 py-2">
            Аналитика
          </TabsTrigger>
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
                            {transaction.payload?.description || `${typeLabels[transaction.type]} ${formatKZT(transaction.amount_kzt)}`}
                          </p>
                          <div className="flex items-center flex-wrap gap-2 text-xs text-muted-foreground">
                            {transaction.source_user_name && (
                              <span className="text-foreground font-medium">За: {transaction.source_user_name}</span>
                            )}
                            <span>{new Date(transaction.created_at).toLocaleString('ru-RU')}</span>
                          </div>
                        </div>
                        <div className={`text-lg font-bold ${
                          ['commission', 'bonus'].includes(transaction.type) ? "text-success" : "text-muted-foreground"
                        }`}>
                          {['commission', 'bonus'].includes(transaction.type) ? '+' : '-'}
                          {formatKZT(transaction.amount_kzt)}
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="withdrawals" className="space-y-6">
          <WithdrawalsHistory ownOnly />
        </TabsContent>

        <TabsContent value="structure1" className="space-y-6">
          <SubscriptionStructure
            levels={structure1Levels || []}
            isLoading={structure1Loading}
            directReferrals={0}
            subscriptionExpiresAt={profile?.subscription_expires_at || null}
          />
        </TabsContent>

        <TabsContent value="structure2" className="space-y-6">
          <ProductStructure
            levels={structure2Levels || []}
            isLoading={structure2Loading}
            subscriptionActive={profile?.subscription_status === 'active'}
            monthlyActivationMet={profile?.monthly_activation_completed || false}
          />
        </TabsContent>

        <TabsContent value="analytics" className="space-y-6">
          <div className="grid gap-6 md:grid-cols-2">
            <Card className="financial-card">
              <CardHeader>
                <CardTitle>Доходы по месяцам</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {monthlyWithChange.length === 0 ? (
                    <p className="text-muted-foreground">Нет данных</p>
                  ) : (
                    monthlyWithChange.map((data, index) => (
                      <div key={index} className="flex items-center justify-between">
                        <span className="text-sm">{data.month}</span>
                        <div className="flex items-center space-x-2">
                          <span className="font-medium">{formatKZT(data.amountCents)}</span>
                          <Badge className="profit-indicator text-xs">
                            {data.change >= 0 ? `+${data.change}%` : `${data.change}%`}
                          </Badge>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </CardContent>
            </Card>

            <Card className="financial-card">
              <CardHeader>
                <CardTitle>Источники дохода</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {totalSources === 0 ? (
                    <p className="text-muted-foreground">Нет данных за выбранный период</p>
                  ) : (
                    [
                      { source: "Прямые комиссии", amountCents: directCents },
                      { source: "Командные бонусы", amountCents: teamBonusCents },
                      { source: "Активационные", amountCents: activationCents }
                    ].map((data, index) => {
                      const percent = totalSources > 0 ? Math.round((data.amountCents / totalSources) * 100) : 0;
                      return (
                        <div key={index} className="space-y-2">
                          <div className="flex items-center justify-between">
                            <span className="text-sm">{data.source}</span>
                            <span className="font-medium">{formatKZT(data.amountCents)}</span>
                          </div>
                          <div className="w-full bg-muted rounded-full h-2">
                            <div 
                              className="bg-primary h-2 rounded-full" 
                              style={{ width: `${percent}%` }}
                            ></div>
                          </div>
                        </div>
                      );
                    })
                  )}
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