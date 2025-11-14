import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DollarSign, TrendingUp, Users, ShoppingCart, Download, Loader2 } from "lucide-react";
import { useAdminGlobalStats, useAdminStructureStats } from "@/hooks/useAdminStats";
import { formatCents } from "@/utils/formatMoney";
import { useState } from "react";
import { downloadCSV } from "@/utils/exportCSV";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";

export default function AdminReports() {
  const [showArchived, setShowArchived] = useState(false);
  const [dateRange] = useState({
    start: new Date(new Date().setDate(1)), // начало месяца
    end: new Date()
  });

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
      value: formatCents(globalStats?.total_revenue_cents || 0),
      change: "за текущий месяц",
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
      value: formatCents(globalStats?.avg_order_cents || 0),
      change: "в USD",
      icon: TrendingUp,
    },
  ];

  const handleExportStructure = (structureType: 1 | 2) => {
    const data = structureType === 1 ? structure1Stats : structure2Stats;
    if (!data) return;

    const csvData = data.map(row => ({
      'Уровень': `L${row.level}`,
      'Процент': `${row.percent}%`,
      'Транзакций': row.transactions_count,
      'Выплачено (USD)': (row.total_amount_cents / 100).toFixed(2),
      'Заморожено (USD)': (row.frozen_amount_cents / 100).toFixed(2),
      'Pass-up': row.pass_up_count
    }));

    downloadCSV(
      csvData,
      `structure_${structureType}_report_${new Date().toISOString().split('T')[0]}.csv`
    );
  };

  if (globalLoading) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 md:p-8 space-y-4 sm:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <h1 className="text-2xl sm:text-3xl font-bold">Финансовые отчеты</h1>
        <div className="flex items-center gap-2">
          <Switch
            checked={showArchived}
            onCheckedChange={setShowArchived}
            id="show-archived-reports"
          />
          <Label htmlFor="show-archived-reports" className="text-sm">Показывать архивные</Label>
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
                <div className="flex justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
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
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Выплачено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Заморожено</TableHead>
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
                              <TableCell className="text-right text-xs sm:text-sm text-success font-medium">
                                {formatCents(row.total_amount_cents)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-warning">
                                {formatCents(row.frozen_amount_cents)}
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
                <div className="flex justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
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
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Выплачено</TableHead>
                            <TableHead className="text-right whitespace-nowrap text-xs sm:text-sm">Pass-up</TableHead>
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
                              <TableCell className="text-right text-xs sm:text-sm text-success font-medium">
                                {formatCents(row.total_amount_cents)}
                              </TableCell>
                              <TableCell className="text-right text-xs sm:text-sm text-muted-foreground">
                                {row.pass_up_count}
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
