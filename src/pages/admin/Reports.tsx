import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DollarSign, TrendingUp, Users, ShoppingCart, Download, RefreshCw, CalendarIcon } from "lucide-react";
import { useAdminGlobalStats, useAdminStructureStats } from "@/hooks/useAdminStats";
import { Skeleton } from "@/components/ui/skeleton";
import { formatKZT } from "@/utils/formatMoney";
import { useState, useMemo } from "react";
import { downloadCSV } from "@/utils/exportCSV";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { useQueryClient } from "@tanstack/react-query";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

type PeriodType = 'current_month' | 'last_month' | 'quarter' | 'half_year' | 'year' | 'all';

const periodLabels: Record<PeriodType, string> = {
  current_month: 'Текущий месяц',
  last_month: 'Прошлый месяц',
  quarter: 'За квартал',
  half_year: 'За полгода',
  year: 'За год',
  all: 'Весь период'
};

export default function AdminReports() {
  const [showArchived, setShowArchived] = useState(false);
  const [period, setPeriod] = useState<PeriodType>('current_month');
  const queryClient = useQueryClient();
  
  const dateRange = useMemo(() => {
    const now = new Date();
    let start = new Date();
    let end = now;
    
    switch (period) {
      case 'current_month':
        start = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      case 'last_month':
        start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        end = new Date(now.getFullYear(), now.getMonth(), 0);
        break;
      case 'quarter':
        start = new Date(now.getFullYear(), now.getMonth() - 3, 1);
        break;
      case 'half_year':
        start = new Date(now.getFullYear(), now.getMonth() - 6, 1);
        break;
      case 'year':
        start = new Date(now.getFullYear() - 1, now.getMonth(), 1);
        break;
      case 'all':
        start = new Date(2020, 0, 1);
        break;
    }
    
    return { start, end };
  }, [period]);

  const periodLabel = useMemo(() => {
    if (period === 'all') return 'за всё время';
    return `${format(dateRange.start, 'd MMM', { locale: ru })} - ${format(dateRange.end, 'd MMM yyyy', { locale: ru })}`;
  }, [period, dateRange]);

  const { data: globalStats, isLoading: globalLoading } = useAdminGlobalStats(
    dateRange.start,
    dateRange.end,
    showArchived
  );
  
  const { data: structure1Stats, isLoading: s1Loading } = useAdminStructureStats(1, dateRange.start, dateRange.end);
  const { data: structure2Stats, isLoading: s2Loading } = useAdminStructureStats(2, dateRange.start, dateRange.end);

  const stats = [
    {
      title: "Общий доход",
      value: formatKZT(globalStats?.total_revenue_kzt || 0),
      change: periodLabel,
      icon: DollarSign,
    },
    {
      title: "Активные пользователи",
      value: globalStats?.active_users_count || 0,
      change: `${globalStats?.subscriptions_count || 0} с подпиской`,
      icon: Users,
    },
    {
      title: "Заказы",
      value: globalStats?.orders_count || 0,
      change: "оплаченных заказов",
      icon: ShoppingCart,
    },
    {
      title: "Средний чек",
      value: formatKZT(globalStats?.avg_order_kzt || 0),
      change: "в тенге",
      icon: TrendingUp,
    },
  ];

  const handleRefresh = () => {
    queryClient.invalidateQueries({ queryKey: ['admin-global-stats'] });
    queryClient.invalidateQueries({ queryKey: ['admin-structure-stats'] });
  };

  const handleExportStructure = (structureType: 1 | 2) => {
    const data = structureType === 1 ? structure1Stats : structure2Stats;
    if (!data) return;

    const csvData = data.map(row => ({
      'Уровень': `L${row.level}`,
      'Процент': `${row.percent}%`,
      'Транзакций': row.transactions_count,
      'Начислено (KZT)': row.total_amount_kzt,
      'Заморожено (KZT)': row.frozen_amount_kzt,
      'Доступно (KZT)': row.available_amount_kzt || 0,
      'Pass-up': row.pass_up_count
    }));

    downloadCSV(
      csvData,
      `structure_${structureType}_report_${new Date().toISOString().split('T')[0]}.csv`
    );
  };

  if (globalLoading) {
    return (
      <div className="p-4 sm:p-6 md:p-8 space-y-4 sm:space-y-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <Skeleton className="h-9 w-64" />
          <div className="flex gap-2">
            <Skeleton className="h-10 w-40" />
            <Skeleton className="h-10 w-24" />
          </div>
        </div>
        <div className="grid gap-3 sm:gap-4 grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <Card key={i}>
              <CardHeader className="pb-2">
                <Skeleton className="h-4 w-24" />
              </CardHeader>
              <CardContent>
                <Skeleton className="h-8 w-20 mb-1" />
                <Skeleton className="h-3 w-16" />
              </CardContent>
            </Card>
          ))}
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <Skeleton className="h-32" />
          <Skeleton className="h-32" />
        </div>
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 md:p-8 space-y-4 sm:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <h1 className="text-2xl sm:text-3xl font-bold">Финансовые отчеты</h1>
        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
          <Select value={period} onValueChange={(v) => setPeriod(v as PeriodType)}>
            <SelectTrigger className="w-[160px]">
              <CalendarIcon className="h-4 w-4 mr-2" />
              <SelectValue placeholder="Период" />
            </SelectTrigger>
            <SelectContent>
              {Object.entries(periodLabels).map(([key, label]) => (
                <SelectItem key={key} value={key}>{label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            variant="outline"
            size="sm"
            onClick={handleRefresh}
            disabled={globalLoading || s1Loading || s2Loading}
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${(globalLoading || s1Loading || s2Loading) ? 'animate-spin' : ''}`} />
            Обновить
          </Button>
          <div className="flex items-center gap-2">
            <Switch
              checked={showArchived}
              onCheckedChange={setShowArchived}
              id="show-archived-reports"
            />
            <Label htmlFor="show-archived-reports" className="text-sm">Архив</Label>
          </div>
        </div>
      </div>

      <div className="grid gap-3 sm:gap-4 grid-cols-2 lg:grid-cols-4">
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

      {/* Structure Summary Cards */}
      <div className="grid gap-4 md:grid-cols-2">
        {/* S1 Summary */}
        <Card className="border-l-4 border-l-primary">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Users className="h-5 w-5" />
              Структура 1 — Абонентская (L1-L5)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {s1Loading ? (
              <div className="grid grid-cols-3 gap-4">
                {[1, 2, 3].map((i) => <Skeleton key={i} className="h-14" />)}
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-4 text-sm">
                <div>
                  <p className="text-muted-foreground">Транзакций</p>
                  <p className="text-xl font-bold">
                    {(structure1Stats || []).reduce((sum, r) => sum + r.transactions_count, 0)}
                  </p>
                </div>
                <div>
                  <p className="text-muted-foreground">Начислено</p>
                  <p className="text-xl font-bold text-success">
                    {formatKZT((structure1Stats || []).reduce((sum, r) => sum + r.total_amount_kzt, 0))}
                  </p>
                </div>
                <div>
                  <p className="text-muted-foreground">Заморожено</p>
                  <p className="text-xl font-bold text-warning">
                    {formatKZT((structure1Stats || []).reduce((sum, r) => sum + r.frozen_amount_kzt, 0))}
                  </p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* S2 Summary */}
        <Card className="border-l-4 border-l-secondary">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <ShoppingCart className="h-5 w-5" />
              Структура 2 — Товарная (L1-L10)
            </CardTitle>
          </CardHeader>
          <CardContent>
            {s2Loading ? (
              <div className="grid grid-cols-3 gap-4">
                {[1, 2, 3].map((i) => <Skeleton key={i} className="h-14" />)}
              </div>
            ) : (
              <div className="grid grid-cols-3 gap-4 text-sm">
                <div>
                  <p className="text-muted-foreground">Транзакций</p>
                  <p className="text-xl font-bold">
                    {(structure2Stats || []).reduce((sum, r) => sum + r.transactions_count, 0)}
                  </p>
                </div>
                <div>
                  <p className="text-muted-foreground">Начислено</p>
                  <p className="text-xl font-bold text-success">
                    {formatKZT((structure2Stats || []).reduce((sum, r) => sum + r.total_amount_kzt, 0))}
                  </p>
                </div>
                <div>
                  <p className="text-muted-foreground">Заморожено</p>
                  <p className="text-xl font-bold text-warning">
                    {formatKZT((structure2Stats || []).reduce((sum, r) => sum + r.frozen_amount_kzt, 0))}
                  </p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Детальные отчеты</CardTitle>
        </CardHeader>
        <CardContent>
          <Tabs defaultValue="structure1">
            <TabsList className="grid w-full grid-cols-3 text-xs sm:text-sm">
              <TabsTrigger value="structure1">Абонентская (S1)</TabsTrigger>
              <TabsTrigger value="structure2">Товарная (S2)</TabsTrigger>
              <TabsTrigger value="frozen">Заморозки</TabsTrigger>
            </TabsList>

            <TabsContent value="structure1" className="space-y-4">
              <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
                <h3 className="text-base sm:text-lg font-semibold break-words">
                  Абонентская структура (5 уровней)
                </h3>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full sm:w-auto text-xs sm:text-sm"
                  onClick={() => handleExportStructure(1)}
                  disabled={s1Loading || !structure1Stats?.length}
                >
                  <Download className="h-3 w-3 sm:h-4 sm:w-4 mr-2" />
                  CSV
                </Button>
              </div>
              
              {s1Loading ? (
                <div className="space-y-2">
                  {[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-12 w-full" />)}
                </div>
              ) : (
                <div className="overflow-x-auto -mx-4 sm:mx-0">
                  <div className="inline-block min-w-full align-middle">
                    <div className="overflow-hidden border rounded-lg">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="whitespace-nowrap text-xs sm:text-sm">Уровень</TableHead>
                            <TableHead className="whitespace-nowrap text-xs sm:text-sm">Процент</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Транзакций</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Начислено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Заморожено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Доступно</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {(structure1Stats || []).map((row) => (
                            <TableRow key={row.level}>
                              <TableCell className="text-xs sm:text-sm">
                                <Badge variant="outline" className="text-xs">L{row.level}</Badge>
                              </TableCell>
                              <TableCell className="text-xs sm:text-sm font-medium">{row.percent}%</TableCell>
                              <TableCell className="text-right text-xs sm:text-sm">{row.transactions_count}</TableCell>
                              <TableCell className="text-right text-xs sm:text-sm font-medium">
                                {formatKZT(row.total_amount_kzt)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-warning">
                                {formatKZT(row.frozen_amount_kzt)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-success font-medium">
                                {formatKZT(row.available_amount_kzt || 0)}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  </div>
                </div>
              )}
            </TabsContent>

            <TabsContent value="structure2" className="space-y-4">
              <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
                <h3 className="text-base sm:text-lg font-semibold break-words">
                  Товарная структура (10 уровней)
                </h3>
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full sm:w-auto text-xs sm:text-sm"
                  onClick={() => handleExportStructure(2)}
                  disabled={s2Loading || !structure2Stats?.length}
                >
                  <Download className="h-3 w-3 sm:h-4 sm:w-4 mr-2" />
                  CSV
                </Button>
              </div>
              
              {s2Loading ? (
                <div className="space-y-2">
                  {[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-12 w-full" />)}
                </div>
              ) : (
                <div className="overflow-x-auto -mx-4 sm:mx-0">
                  <div className="inline-block min-w-full align-middle">
                    <div className="overflow-hidden border rounded-lg">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead className="whitespace-nowrap text-xs sm:text-sm">Уровень</TableHead>
                            <TableHead className="whitespace-nowrap text-xs sm:text-sm">Процент</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Транзакций</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Начислено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Заморожено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Доступно</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {(structure2Stats || []).map((row) => (
                            <TableRow key={row.level}>
                              <TableCell className="text-xs sm:text-sm">
                                <Badge variant="outline" className="text-xs">L{row.level}</Badge>
                              </TableCell>
                              <TableCell className="text-xs sm:text-sm font-medium">{row.percent}%</TableCell>
                              <TableCell className="text-right text-xs sm:text-sm">{row.transactions_count}</TableCell>
                              <TableCell className="text-right text-xs sm:text-sm font-medium">
                                {formatKZT(row.total_amount_kzt)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-warning">
                                {formatKZT(row.frozen_amount_kzt)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-success font-medium">
                                {formatKZT(row.available_amount_kzt || 0)}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  </div>
                </div>
              )}
            </TabsContent>

            <TabsContent value="frozen">
              <div className="space-y-4">
                <h3 className="text-base sm:text-lg font-semibold break-words">
                  Замороженные пользователи (структура 1)
                </h3>
                <div className="p-4 sm:p-6 bg-muted/50 rounded-lg text-center">
                  <p className="text-sm sm:text-base text-muted-foreground mb-2">
                    Пользователей с истёкшей подпиской:
                  </p>
                  <p className="text-2xl sm:text-3xl font-bold text-warning">
                    {globalStats?.frozen_users_count || 0}
                  </p>
                  <p className="text-xs text-muted-foreground mt-2">
                    Начисления этих пользователей заморожены до продления подписки
                  </p>
                </div>
              </div>
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  );
}
