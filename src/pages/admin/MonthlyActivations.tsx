import { useState, useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { 
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow 
} from "@/components/ui/table";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue
} from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { 
  Search, RefreshCw, Calendar, CheckCircle2, XCircle, 
  ChevronLeft, ChevronRight, Eye, Package, User, Download,
  Edit2, Save, X, Loader2
} from "lucide-react";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import {
  useMonthlyActivationsReport,
  useMonthlyActivationsCounts,
  usePartnerOrdersForMonth,
  useRecalculateMonthlyActivations,
  useUpdateActivationComment,
  useExportAllActivations,
  type ActivationReportItem
} from "@/hooks/useMonthlyActivations";
import { formatMoney } from "@/utils/formatMoney";
import { exportActivationsToCSV } from "@/utils/exportCSV";

const MONTHS = [
  { value: 1, label: "Январь" },
  { value: 2, label: "Февраль" },
  { value: 3, label: "Март" },
  { value: 4, label: "Апрель" },
  { value: 5, label: "Май" },
  { value: 6, label: "Июнь" },
  { value: 7, label: "Июль" },
  { value: 8, label: "Август" },
  { value: 9, label: "Сентябрь" },
  { value: 10, label: "Октябрь" },
  { value: 11, label: "Ноябрь" },
  { value: 12, label: "Декабрь" }
];

const ITEMS_PER_PAGE = 20;

export default function MonthlyActivations() {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [status, setStatus] = useState<'all' | 'activated' | 'not_activated'>('all');
  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [page, setPage] = useState(0);
  const [selectedPartner, setSelectedPartner] = useState<ActivationReportItem | null>(null);
  const [editingComment, setEditingComment] = useState<{
    userId: string;
    comment: string;
  } | null>(null);

  // Debounce search
  const handleSearchChange = (value: string) => {
    setSearch(value);
    setPage(0);
    const timeout = setTimeout(() => setDebouncedSearch(value), 300);
    return () => clearTimeout(timeout);
  };

  // Queries
  const { data: reportData, isLoading: reportLoading, refetch } = useMonthlyActivationsReport({
    year,
    month,
    status,
    search: debouncedSearch,
    limit: ITEMS_PER_PAGE,
    offset: page * ITEMS_PER_PAGE
  });

  const { data: counts, isLoading: countsLoading } = useMonthlyActivationsCounts(
    year, month, debouncedSearch
  );

  const { data: partnerOrders, isLoading: ordersLoading } = usePartnerOrdersForMonth(
    selectedPartner?.user_id || null,
    year,
    month
  );

  const recalculateMutation = useRecalculateMonthlyActivations();
  const updateCommentMutation = useUpdateActivationComment();
  const exportAllMutation = useExportAllActivations();

  // Years for selector (last 3 years)
  const years = useMemo(() => {
    const currentYear = now.getFullYear();
    return [currentYear, currentYear - 1, currentYear - 2];
  }, []);

  const handleRecalculate = () => {
    recalculateMutation.mutate({ year, month });
  };

  const handleRecalculateAll = () => {
    if (confirm('Пересчитать активации за все периоды? Это может занять некоторое время.')) {
      recalculateMutation.mutate({});
    }
  };

  const handleExportAll = async () => {
    const data = await exportAllMutation.mutateAsync({
      year,
      month,
      status,
      search: debouncedSearch
    });
    if (data && data.length > 0) {
      exportActivationsToCSV(data, month, year);
    }
  };

  const handleSaveComment = () => {
    if (!editingComment) return;
    updateCommentMutation.mutate({
      userId: editingComment.userId,
      year,
      month,
      comment: editingComment.comment
    }, {
      onSuccess: () => setEditingComment(null)
    });
  };

  const totalPages = counts ? Math.ceil(
    (status === 'all' ? counts.total : 
     status === 'activated' ? counts.activated : counts.not_activated) 
    / ITEMS_PER_PAGE
  ) : 0;

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Ежемесячные активации</h1>
          <p className="text-sm text-muted-foreground">
            Отчёт по активациям партнёров (структура 2)
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={handleExportAll}
            disabled={exportAllMutation.isPending || countsLoading || (counts?.total || 0) === 0}
          >
            {exportAllMutation.isPending ? (
              <Loader2 className="w-4 h-4 mr-2 animate-spin" />
            ) : (
              <Download className="w-4 h-4 mr-2" />
            )}
            Выгрузить Excel ({counts?.total || 0})
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={handleRecalculate}
            disabled={recalculateMutation.isPending}
          >
            <RefreshCw className={`w-4 h-4 mr-2 ${recalculateMutation.isPending ? 'animate-spin' : ''}`} />
            Пересчитать месяц
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleRecalculateAll}
            disabled={recalculateMutation.isPending}
          >
            Пересчитать всё
          </Button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Всего партнёров</p>
                {countsLoading ? (
                  <Skeleton className="h-8 w-16 mt-1" />
                ) : (
                  <p className="text-2xl font-bold">{counts?.total || 0}</p>
                )}
              </div>
              <User className="w-8 h-8 text-muted-foreground" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-green-500/30 bg-green-500/5">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Активировано</p>
                {countsLoading ? (
                  <Skeleton className="h-8 w-16 mt-1" />
                ) : (
                  <p className="text-2xl font-bold text-green-600">{counts?.activated || 0}</p>
                )}
              </div>
              <CheckCircle2 className="w-8 h-8 text-green-500" />
            </div>
          </CardContent>
        </Card>
        <Card className="border-red-500/30 bg-red-500/5">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Не активировано</p>
                {countsLoading ? (
                  <Skeleton className="h-8 w-16 mt-1" />
                ) : (
                  <p className="text-2xl font-bold text-red-600">{counts?.not_activated || 0}</p>
                )}
              </div>
              <XCircle className="w-8 h-8 text-red-500" />
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">Порог активации</p>
                <p className="text-2xl font-bold">{formatMoney(counts?.threshold_kzt || 20000, 'KZT')}</p>
              </div>
              <Package className="w-8 h-8 text-muted-foreground" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="pt-6">
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex items-center gap-2">
              <Calendar className="w-4 h-4 text-muted-foreground" />
              <Select value={month.toString()} onValueChange={(v) => { setMonth(Number(v)); setPage(0); }}>
                <SelectTrigger className="w-[140px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {MONTHS.map(m => (
                    <SelectItem key={m.value} value={m.value.toString()}>
                      {m.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={year.toString()} onValueChange={(v) => { setYear(Number(v)); setPage(0); }}>
                <SelectTrigger className="w-[100px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {years.map(y => (
                    <SelectItem key={y} value={y.toString()}>{y}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <Select value={status} onValueChange={(v: any) => { setStatus(v); setPage(0); }}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Статус" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Все</SelectItem>
                <SelectItem value="activated">Активные</SelectItem>
                <SelectItem value="not_activated">Не активные</SelectItem>
              </SelectContent>
            </Select>

            <div className="relative flex-1 min-w-[200px]">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder="Поиск по имени, email или коду..."
                value={search}
                onChange={(e) => handleSearchChange(e.target.value)}
                className="pl-10"
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Table */}
      <Card>
        <CardHeader>
          <CardTitle>
            Партнёры за {MONTHS.find(m => m.value === month)?.label} {year}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {reportLoading ? (
            <div className="space-y-3">
              {[...Array(5)].map((_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : reportData && reportData.length > 0 ? (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Партнёр</TableHead>
                    <TableHead className="text-right">Сумма заказов</TableHead>
                    <TableHead className="text-right">Порог</TableHead>
                    <TableHead className="text-center">Статус</TableHead>
                    <TableHead className="text-center">Заказов</TableHead>
                    <TableHead>Дата активации</TableHead>
                    <TableHead>Последний заказ</TableHead>
                    <TableHead className="min-w-[200px]">Комментарий</TableHead>
                    <TableHead className="w-[50px]"></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {reportData.map((item) => (
                    <TableRow key={item.user_id}>
                      <TableCell>
                        <div>
                          <p className="font-medium">{item.full_name || 'Без имени'}</p>
                          <p className="text-sm text-muted-foreground">{item.email}</p>
                          <p className="text-xs text-muted-foreground">Код: {item.referral_code}</p>
                        </div>
                      </TableCell>
                      <TableCell className="text-right font-medium">
                        {formatMoney(item.total_amount_kzt, 'KZT')}
                      </TableCell>
                      <TableCell className="text-right text-muted-foreground">
                        {formatMoney(item.threshold_kzt, 'KZT')}
                      </TableCell>
                      <TableCell className="text-center">
                        {item.is_activated ? (
                          <Badge className="bg-green-500">Активен</Badge>
                        ) : (
                          <Badge variant="outline" className="text-orange-500 border-orange-500">
                            {formatMoney(item.total_amount_kzt, 'KZT')} / {formatMoney(item.threshold_kzt, 'KZT')}
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-center">
                        {item.orders_count}
                      </TableCell>
                      <TableCell>
                        {item.activation_due_from ? (
                          format(new Date(item.activation_due_from), 'dd.MM.yyyy', { locale: ru })
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {item.last_order_date ? (
                          format(new Date(item.last_order_date), 'dd.MM.yyyy HH:mm', { locale: ru })
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {editingComment?.userId === item.user_id ? (
                          <div className="flex items-center gap-2">
                            <Textarea
                              value={editingComment.comment}
                              onChange={(e) => setEditingComment({ ...editingComment, comment: e.target.value })}
                              className="min-h-[60px] text-sm"
                              placeholder="Комментарий..."
                            />
                            <div className="flex flex-col gap-1">
                              <Button 
                                size="sm" 
                                onClick={handleSaveComment}
                                disabled={updateCommentMutation.isPending}
                              >
                                <Save className="h-4 w-4" />
                              </Button>
                              <Button 
                                size="sm" 
                                variant="ghost" 
                                onClick={() => setEditingComment(null)}
                              >
                                <X className="h-4 w-4" />
                              </Button>
                            </div>
                          </div>
                        ) : (
                          <div className="flex items-center gap-2">
                            <span className="text-sm text-muted-foreground truncate max-w-[150px]">
                              {item.admin_comment || '—'}
                            </span>
                            <Button
                              size="sm"
                              variant="ghost"
                              onClick={() => setEditingComment({
                                userId: item.user_id,
                                comment: item.admin_comment || ''
                              })}
                            >
                              <Edit2 className="h-4 w-4" />
                            </Button>
                          </div>
                        )}
                      </TableCell>
                      <TableCell>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setSelectedPartner(item)}
                        >
                          <Eye className="w-4 h-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              {/* Pagination */}
              {totalPages > 1 && (
                <div className="flex items-center justify-between mt-4">
                  <p className="text-sm text-muted-foreground">
                    Страница {page + 1} из {totalPages}
                  </p>
                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setPage(p => Math.max(0, p - 1))}
                      disabled={page === 0}
                    >
                      <ChevronLeft className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setPage(p => Math.min(totalPages - 1, p + 1))}
                      disabled={page >= totalPages - 1}
                    >
                      <ChevronRight className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              )}
            </>
          ) : (
            <div className="text-center py-8 text-muted-foreground">
              <Package className="w-12 h-12 mx-auto mb-4 opacity-50" />
              <p>Нет данных за выбранный период</p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Partner Orders Dialog */}
      <Dialog open={!!selectedPartner} onOpenChange={() => setSelectedPartner(null)}>
        <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              Заказы партнёра за {MONTHS.find(m => m.value === month)?.label} {year}
            </DialogTitle>
          </DialogHeader>
          
          {selectedPartner && (
            <div className="space-y-4">
              <div className="p-4 bg-muted rounded-lg">
                <p className="font-medium">{selectedPartner.full_name}</p>
                <p className="text-sm text-muted-foreground">{selectedPartner.email}</p>
                <div className="flex items-center gap-4 mt-2">
                  <span className="text-sm">
                    Всего: <strong>{formatMoney(selectedPartner.total_amount_kzt, 'KZT')}</strong>
                  </span>
                  {selectedPartner.is_activated ? (
                    <Badge className="bg-green-500">Активирован</Badge>
                  ) : (
                    <Badge variant="outline" className="text-orange-500 border-orange-500">
                      Не хватает {formatMoney(selectedPartner.threshold_kzt - selectedPartner.total_amount_kzt, 'KZT')}
                    </Badge>
                  )}
                </div>
              </div>

              {ordersLoading ? (
                <div className="space-y-3">
                  {[...Array(3)].map((_, i) => (
                    <Skeleton key={i} className="h-20 w-full" />
                  ))}
                </div>
              ) : partnerOrders && partnerOrders.length > 0 ? (
                <div className="space-y-3">
                  {partnerOrders.map((order) => (
                    <Card key={order.order_id}>
                      <CardContent className="pt-4">
                        <div className="flex items-start justify-between mb-2">
                          <div>
                            <p className="font-medium">
                              Заказ от {format(new Date(order.order_date), 'dd.MM.yyyy HH:mm', { locale: ru })}
                            </p>
                            <p className="text-xs text-muted-foreground">
                              ID: {order.order_id.slice(0, 8)}...
                            </p>
                          </div>
                          <div className="text-right">
                            <p className="font-bold">{formatMoney(order.total_kzt, 'KZT')}</p>
                            <Badge variant="outline" className="text-green-500">
                              {order.status}
                            </Badge>
                          </div>
                        </div>
                        {order.items && order.items.length > 0 && (
                          <div className="border-t pt-2 mt-2">
                            <p className="text-sm text-muted-foreground mb-1">Товары:</p>
                            {order.items.map((item, idx) => (
                              <div key={idx} className="flex items-center justify-between text-sm">
                                <span className="flex items-center gap-1">
                                  {item.title || 'Товар'}
                                  {item.is_activation && (
                                    <Badge variant="secondary" className="text-xs">Активация</Badge>
                                  )}
                                </span>
                                <span>
                                  {item.qty} × {formatMoney(item.price_kzt, 'KZT')}
                                </span>
                              </div>
                            ))}
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : (
                <div className="text-center py-8 text-muted-foreground">
                  <Package className="w-8 h-8 mx-auto mb-2 opacity-50" />
                  <p>Нет оплаченных заказов за этот период</p>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
