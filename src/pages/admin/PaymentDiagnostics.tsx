import { useState } from "react";
import { Helmet } from "react-helmet";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { AlertCircle, RefreshCw, CheckCircle2, XCircle, Clock, Activity, CreditCard, ShoppingCart } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { usePaymentDiagnostics, useReprocessPayment, PaymentError } from "@/hooks/usePaymentDiagnostics";
import { formatMoney } from "@/utils/formatMoney";

export default function PaymentDiagnostics() {
  const { data, isLoading, refetch, isRefetching } = usePaymentDiagnostics();
  const reprocessMutation = useReprocessPayment();
  const [processingId, setProcessingId] = useState<string | null>(null);

  const handleReprocess = async (recordType: 'subscription' | 'order', recordId: string) => {
    if (!recordId) return;
    setProcessingId(recordId);
    try {
      await reprocessMutation.mutateAsync({ recordType, recordId });
    } finally {
      setProcessingId(null);
    }
  };

  const getErrorBadge = (errorType: string) => {
    switch (errorType) {
      case 'sponsor_not_eligible':
        return <Badge variant="outline" className="text-amber-600 border-amber-600">Спонсор не активен</Badge>;
      case 'duplicate_key':
        return <Badge variant="outline" className="text-red-600 border-red-600">Дубликат</Badge>;
      default:
        return <Badge variant="outline">{errorType}</Badge>;
    }
  };

  if (isLoading) {
    return (
      <div className="p-6 space-y-6">
        <Skeleton className="h-8 w-64" />
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map(i => <Skeleton key={i} className="h-24" />)}
        </div>
        <Skeleton className="h-96" />
      </div>
    );
  }

  const stats = data?.stats || { totalErrors: 0, skippedCommissions: 0, pendingSubscriptions: 0, pendingOrders: 0 };

  return (
    <>
      <Helmet>
        <title>Диагностика оплат | Админ</title>
      </Helmet>

      <div className="p-6 space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Activity className="h-6 w-6 text-primary" />
              Диагностика оплат
            </h1>
            <p className="text-muted-foreground mt-1">
              Мониторинг ошибок обработки платежей и комиссий
            </p>
          </div>
          <Button 
            onClick={() => refetch()} 
            disabled={isRefetching}
            variant="outline"
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${isRefetching ? 'animate-spin' : ''}`} />
            Обновить
          </Button>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-muted-foreground">Всего ошибок</p>
                  <p className="text-2xl font-bold">{stats.totalErrors}</p>
                </div>
                <AlertCircle className={`h-8 w-8 ${stats.totalErrors > 0 ? 'text-destructive' : 'text-muted-foreground'}`} />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-muted-foreground">Пропущенных комиссий</p>
                  <p className="text-2xl font-bold">{stats.skippedCommissions}</p>
                </div>
                <XCircle className={`h-8 w-8 ${stats.skippedCommissions > 0 ? 'text-amber-500' : 'text-muted-foreground'}`} />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-muted-foreground">Ожидающих подписок</p>
                  <p className="text-2xl font-bold">{stats.pendingSubscriptions}</p>
                </div>
                <CreditCard className={`h-8 w-8 ${stats.pendingSubscriptions > 0 ? 'text-blue-500' : 'text-muted-foreground'}`} />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-muted-foreground">Ожидающих заказов</p>
                  <p className="text-2xl font-bold">{stats.pendingOrders}</p>
                </div>
                <ShoppingCart className={`h-8 w-8 ${stats.pendingOrders > 0 ? 'text-blue-500' : 'text-muted-foreground'}`} />
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Main Content */}
        <Tabs defaultValue="errors" className="w-full">
          <TabsList>
            <TabsTrigger value="errors">
              Ошибки комиссий
              {stats.skippedCommissions > 0 && (
                <Badge variant="destructive" className="ml-2 h-5 min-w-5">
                  {stats.skippedCommissions}
                </Badge>
              )}
            </TabsTrigger>
            <TabsTrigger value="pending-subscriptions">
              Ожидающие подписки
              {stats.pendingSubscriptions > 0 && (
                <Badge variant="secondary" className="ml-2 h-5 min-w-5">
                  {stats.pendingSubscriptions}
                </Badge>
              )}
            </TabsTrigger>
            <TabsTrigger value="pending-orders">
              Ожидающие заказы
              {stats.pendingOrders > 0 && (
                <Badge variant="secondary" className="ml-2 h-5 min-w-5">
                  {stats.pendingOrders}
                </Badge>
              )}
            </TabsTrigger>
          </TabsList>

          <TabsContent value="errors" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>Пропущенные комиссии</CardTitle>
                <CardDescription>
                  Комиссии, которые не были начислены из-за неактивного спонсора или других причин
                </CardDescription>
              </CardHeader>
              <CardContent>
                {(data?.errors?.length || 0) === 0 ? (
                  <div className="flex flex-col items-center justify-center py-12 text-muted-foreground">
                    <CheckCircle2 className="h-12 w-12 mb-4 text-green-500" />
                    <p className="text-lg font-medium">Ошибок не обнаружено</p>
                    <p className="text-sm">Все платежи обработаны корректно</p>
                  </div>
                ) : (
                  <ScrollArea className="h-[400px]">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Дата</TableHead>
                          <TableHead>Тип</TableHead>
                          <TableHead>Пользователь</TableHead>
                          <TableHead>Сумма</TableHead>
                          <TableHead>Причина</TableHead>
                          <TableHead>Детали</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {data?.errors.map((error: PaymentError) => (
                          <TableRow key={error.id}>
                            <TableCell className="whitespace-nowrap">
                              {format(new Date(error.created_at), 'dd.MM.yyyy HH:mm', { locale: ru })}
                            </TableCell>
                            <TableCell>
                              <Badge variant={error.type === 'subscription' ? 'default' : 'secondary'}>
                                {error.type === 'subscription' ? 'Подписка' : 'Заказ'}
                              </Badge>
                            </TableCell>
                            <TableCell>
                              <div>
                                <p className="font-medium">{error.user_name || 'Неизвестно'}</p>
                                <p className="text-xs text-muted-foreground">{error.user_email}</p>
                              </div>
                            </TableCell>
                            <TableCell className="font-mono">
                              {formatMoney(error.amount_kzt, 'KZT')}
                            </TableCell>
                            <TableCell>
                              {getErrorBadge(error.error_type)}
                            </TableCell>
                            <TableCell>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button variant="ghost" size="sm">
                                    <AlertCircle className="h-4 w-4" />
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent className="max-w-xs">
                                  <pre className="text-xs whitespace-pre-wrap">
                                    {JSON.stringify(error.error_details, null, 2)}
                                  </pre>
                                </TooltipContent>
                              </Tooltip>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </ScrollArea>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="pending-subscriptions" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>Ожидающие подписки</CardTitle>
                <CardDescription>
                  Подписки в статусе pending, которые можно обработать вручную
                </CardDescription>
              </CardHeader>
              <CardContent>
                {(data?.pendingSubscriptions?.length || 0) === 0 ? (
                  <div className="flex flex-col items-center justify-center py-12 text-muted-foreground">
                    <CheckCircle2 className="h-12 w-12 mb-4 text-green-500" />
                    <p>Нет ожидающих подписок</p>
                  </div>
                ) : (
                  <ScrollArea className="h-[400px]">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Дата</TableHead>
                          <TableHead>Пользователь</TableHead>
                          <TableHead>Сумма</TableHead>
                          <TableHead>Статус</TableHead>
                          <TableHead>Действия</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {data?.pendingSubscriptions.map((sub: any) => (
                          <TableRow key={sub.id}>
                            <TableCell className="whitespace-nowrap">
                              {format(new Date(sub.created_at), 'dd.MM.yyyy HH:mm', { locale: ru })}
                            </TableCell>
                            <TableCell>
                              <div>
                                <p className="font-medium">{sub.profiles?.full_name || 'Неизвестно'}</p>
                                <p className="text-xs text-muted-foreground">{sub.profiles?.email}</p>
                              </div>
                            </TableCell>
                            <TableCell className="font-mono">
                              {formatMoney(sub.amount_kzt, 'KZT')}
                            </TableCell>
                            <TableCell>
                              <Badge variant="outline" className="text-amber-600 border-amber-600">
                                <Clock className="h-3 w-3 mr-1" />
                                Ожидает
                              </Badge>
                            </TableCell>
                            <TableCell>
                              <Button
                                size="sm"
                                variant="outline"
                                disabled={processingId === sub.id}
                                onClick={() => handleReprocess('subscription', sub.id)}
                              >
                                {processingId === sub.id ? (
                                  <RefreshCw className="h-4 w-4 animate-spin" />
                                ) : (
                                  <>
                                    <RefreshCw className="h-4 w-4 mr-1" />
                                    Обработать
                                  </>
                                )}
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </ScrollArea>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="pending-orders" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>Ожидающие заказы</CardTitle>
                <CardDescription>
                  Заказы в статусе pending, которые можно обработать вручную
                </CardDescription>
              </CardHeader>
              <CardContent>
                {(data?.pendingOrders?.length || 0) === 0 ? (
                  <div className="flex flex-col items-center justify-center py-12 text-muted-foreground">
                    <CheckCircle2 className="h-12 w-12 mb-4 text-green-500" />
                    <p>Нет ожидающих заказов</p>
                  </div>
                ) : (
                  <ScrollArea className="h-[400px]">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Дата</TableHead>
                          <TableHead>ID заказа</TableHead>
                          <TableHead>Сумма</TableHead>
                          <TableHead>Статус</TableHead>
                          <TableHead>Действия</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {data?.pendingOrders.map((order: any) => (
                          <TableRow key={order.id}>
                            <TableCell className="whitespace-nowrap">
                              {format(new Date(order.created_at), 'dd.MM.yyyy HH:mm', { locale: ru })}
                            </TableCell>
                            <TableCell className="font-mono text-xs">
                              {order.id.slice(0, 8)}...
                            </TableCell>
                            <TableCell className="font-mono">
                              {formatMoney(order.total_kzt, 'KZT')}
                            </TableCell>
                            <TableCell>
                              <Badge variant="outline" className="text-amber-600 border-amber-600">
                                <Clock className="h-3 w-3 mr-1" />
                                Ожидает
                              </Badge>
                            </TableCell>
                            <TableCell>
                              <Button
                                size="sm"
                                variant="outline"
                                disabled={processingId === order.id}
                                onClick={() => handleReprocess('order', order.id)}
                              >
                                {processingId === order.id ? (
                                  <RefreshCw className="h-4 w-4 animate-spin" />
                                ) : (
                                  <>
                                    <RefreshCw className="h-4 w-4 mr-1" />
                                    Обработать
                                  </>
                                )}
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </ScrollArea>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </>
  );
}
