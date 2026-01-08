import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatMoney } from "@/utils/formatMoney";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { 
  AlertTriangle, 
  CheckCircle, 
  RefreshCw, 
  TrendingDown, 
  TrendingUp,
  Users,
  DollarSign,
  Activity,
  ShieldCheck,
  ShieldAlert,
  Wrench
} from "lucide-react";
import { toast } from "sonner";

interface BalanceIntegrityIssue {
  user_id: string;
  email: string;
  issue_type: string;
  details: {
    calculated_available?: number;
    profile_balance?: number;
    difference?: number;
    frozen_cents?: number;
    withdrawn_cents?: number;
    [key: string]: any;
  };
}

interface UnlockViolation {
  user_id: string;
  user_email: string;
  user_name: string;
  level: number;
  direct_referrals_count: number;
  required_referrals: number;
  violation_count: number;
  total_wrong_amount_cents: number;
}

interface MarketingFreeIssue {
  user_id: string;
  user_email: string;
  subscription_id: string;
  subscriber_name: string;
  transaction_id: string;
  amount_cents: number;
  issue: string;
}

interface EarlyUnlockIssue {
  transaction_id: string;
  user_id: string;
  user_name: string;
  level: number;
  amount_cents: number;
  structure_type: string;
  source_id: string;
  subscriber_name: string;
  subscription_paid_at: string;
  required_referrals: number;
  actual_referrals_at_time: number;
  status: string;
  created_at: string;
}

interface FixResult {
  success?: boolean;
  dry_run?: boolean;
  fixed_count?: number;
  violations_count?: number;
  violations_found?: number;
  violations_fixed?: number;
  total_amount_cents?: number;
  error?: string;
}

export default function CommissionAudit() {
  const { userRole } = useAuth();
  const queryClient = useQueryClient();
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showDryRun, setShowDryRun] = useState(false);
  const [dryRunResult, setDryRunResult] = useState<FixResult | null>(null);
  const [showMarketingDryRun, setShowMarketingDryRun] = useState(false);
  const [showEarlyDryRun, setShowEarlyDryRun] = useState(false);
  const [earlyDryRunResult, setEarlyDryRunResult] = useState<FixResult | null>(null);
  const [marketingDryRunResult, setMarketingDryRunResult] = useState<any | null>(null);

  // Balance integrity audit
  const { data: balanceIssues, isLoading: loadingBalance, refetch: refetchBalance } = useQuery({
    queryKey: ['audit-balance-integrity'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('audit_balance_integrity');
      if (error) throw error;
      return (data || []) as BalanceIntegrityIssue[];
    },
    staleTime: 60000
  });

  // Unlock level violations audit
  const { data: unlockViolations, isLoading: loadingUnlock, refetch: refetchUnlock } = useQuery({
    queryKey: ['audit-unlock-violations'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('audit_unlock_levels_violations');
      if (error) throw error;
      return (data || []) as UnlockViolation[];
    },
    staleTime: 60000
  });

  // Marketing free commissions audit
  const { data: marketingFreeIssues, isLoading: loadingMarketing, refetch: refetchMarketing } = useQuery({
    queryKey: ['audit-marketing-free'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('audit_marketing_free_commissions');
      if (error) throw error;
      return (data || []) as MarketingFreeIssue[];
    },
    staleTime: 60000
  });

  // Early unlock commissions audit (commissions paid before level was unlocked)
  const { data: earlyUnlockIssues, isLoading: loadingEarly, refetch: refetchEarly } = useQuery({
    queryKey: ['audit-early-unlock'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');
      
      const { data, error } = await supabase.rpc('admin_find_early_unlock_commissions', {
        p_admin_id: user.id,
        p_days_back: 90
      });
      if (error) throw error;
      return (data || []) as EarlyUnlockIssue[];
    },
    staleTime: 60000
  });

  // Fix unlock violations mutation
  const fixViolationsMutation = useMutation({
    mutationFn: async (dryRun: boolean) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');
      
      const { data, error } = await supabase.rpc('admin_fix_unlock_violations', {
        p_admin_id: user.id,
        p_dry_run: dryRun
      });
      
      if (error) throw error;
      return data as FixResult;
    },
    onSuccess: (data, dryRun) => {
      if (dryRun) {
        setDryRunResult(data);
        setShowDryRun(true);
      } else {
        toast.success(`Исправлено ${data.fixed_count} нарушений на сумму ${formatMoney(data.total_amount_cents || 0)}`);
        setShowDryRun(false);
        setDryRunResult(null);
        queryClient.invalidateQueries({ queryKey: ['audit-unlock-violations'] });
        queryClient.invalidateQueries({ queryKey: ['audit-commission-stats'] });
      }
    },
    onError: (error: Error) => {
      toast.error(`Ошибка: ${error.message}`);
    }
  });

  // Fix marketing free violations mutation
  const fixMarketingViolationsMutation = useMutation({
    mutationFn: async (dryRun: boolean) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');
      
      const { data, error } = await supabase.rpc('admin_fix_marketing_free_violations', {
        p_admin_id: user.id,
        p_dry_run: dryRun
      });
      
      if (error) throw error;
      return data as any;
    },
    onSuccess: (data, dryRun) => {
      if (dryRun) {
        setMarketingDryRunResult(data);
        setShowMarketingDryRun(true);
      } else {
        toast.success(`Исправлено ${data.fixed_count} маркетинговых нарушений на сумму ${formatMoney(data.total_amount_cents || 0)}`);
        setShowMarketingDryRun(false);
        setMarketingDryRunResult(null);
        queryClient.invalidateQueries({ queryKey: ['audit-marketing-free'] });
        queryClient.invalidateQueries({ queryKey: ['audit-commission-stats'] });
      }
    },
    onError: (error: Error) => {
      toast.error(`Ошибка: ${error.message}`);
    }
  });

  // Fix early unlock violations mutation
  const fixEarlyViolationsMutation = useMutation({
    mutationFn: async (dryRun: boolean) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');
      
      const { data, error } = await supabase.rpc('admin_fix_early_unlock_commissions', {
        p_admin_id: user.id,
        p_dry_run: dryRun,
        p_days_back: 90
      });
      
      if (error) throw error;
      return data as FixResult;
    },
    onSuccess: (data, dryRun) => {
      if (dryRun) {
        setEarlyDryRunResult(data);
        setShowEarlyDryRun(true);
      } else {
        toast.success(`Исправлено ${data.violations_fixed} ранних комиссий на сумму ${formatMoney(data.total_amount_cents || 0)}`);
        setShowEarlyDryRun(false);
        setEarlyDryRunResult(null);
        queryClient.invalidateQueries({ queryKey: ['audit-early-unlock'] });
        queryClient.invalidateQueries({ queryKey: ['audit-commission-stats'] });
      }
    },
    onError: (error: Error) => {
      toast.error(`Ошибка: ${error.message}`);
    }
  });

  // Commission summary statistics
  const { data: commissionStats, isLoading: loadingStats, refetch: refetchStats } = useQuery({
    queryKey: ['audit-commission-stats'],
    queryFn: async () => {
      // Get S1 commission stats
      const { data: s1Stats, error: s1Error } = await supabase
        .from('transactions')
        .select('amount_cents, status, level, created_at')
        .eq('structure_type', 'primary')
        .eq('type', 'commission')
        .eq('is_archived', false);
      
      if (s1Error) throw s1Error;

      // Get S2 commission stats
      const { data: s2Stats, error: s2Error } = await supabase
        .from('transactions')
        .select('amount_cents, status, level, created_at')
        .eq('structure_type', 'secondary')
        .eq('type', 'commission')
        .eq('is_archived', false);
      
      if (s2Error) throw s2Error;

      const now = new Date();
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

      const calcStats = (data: any[]) => {
        const total = data.reduce((sum, t) => sum + t.amount_cents, 0);
        const frozen = data.filter(t => t.status === 'frozen').reduce((sum, t) => sum + t.amount_cents, 0);
        const completed = data.filter(t => t.status === 'completed').reduce((sum, t) => sum + t.amount_cents, 0);
        const thisMonth = data.filter(t => new Date(t.created_at) >= startOfMonth).reduce((sum, t) => sum + t.amount_cents, 0);
        const byLevel: Record<number, number> = {};
        data.forEach(t => {
          if (t.level) {
            byLevel[t.level] = (byLevel[t.level] || 0) + t.amount_cents;
          }
        });
        return { total, frozen, completed, thisMonth, count: data.length, byLevel };
      };

      return {
        s1: calcStats(s1Stats || []),
        s2: calcStats(s2Stats || [])
      };
    },
    staleTime: 60000
  });

  const handleRefreshAll = async () => {
    setIsRefreshing(true);
    try {
      await Promise.all([
        refetchBalance(),
        refetchUnlock(),
        refetchMarketing(),
        refetchEarly(),
        refetchStats()
      ]);
      toast.success('Данные обновлены');
    } catch (error) {
      toast.error('Ошибка обновления данных');
    } finally {
      setIsRefreshing(false);
    }
  };

  if (userRole !== 'superadmin' && userRole !== 'admin') {
    return (
      <div className="container py-8">
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Доступ запрещён</AlertTitle>
          <AlertDescription>
            Эта страница доступна только администраторам.
          </AlertDescription>
        </Alert>
      </div>
    );
  }

  const totalIssues = (balanceIssues?.length || 0) + (unlockViolations?.length || 0) + (marketingFreeIssues?.length || 0) + (earlyUnlockIssues?.length || 0);
  const hasIssues = totalIssues > 0;

  return (
    <div className="container py-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Аудит комиссий</h1>
          <p className="text-muted-foreground">
            Проверка целостности данных и выявление аномалий
          </p>
        </div>
        <Button onClick={handleRefreshAll} disabled={isRefreshing}>
          <RefreshCw className={`h-4 w-4 mr-2 ${isRefreshing ? 'animate-spin' : ''}`} />
          Обновить всё
        </Button>
      </div>

      {/* Summary Cards */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Статус системы</CardTitle>
            {hasIssues ? (
              <ShieldAlert className="h-4 w-4 text-destructive" />
            ) : (
              <ShieldCheck className="h-4 w-4 text-green-500" />
            )}
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {hasIssues ? (
                <span className="text-destructive">{totalIssues} проблем</span>
              ) : (
                <span className="text-green-500">Всё в порядке</span>
              )}
            </div>
            <p className="text-xs text-muted-foreground">
              Обновлено {format(new Date(), 'HH:mm', { locale: ru })}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">S1 комиссии (всего)</CardTitle>
            <DollarSign className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            {loadingStats ? (
              <Skeleton className="h-7 w-24" />
            ) : (
              <>
                <div className="text-2xl font-bold">
                  {formatMoney(commissionStats?.s1.total || 0)}
                </div>
                <p className="text-xs text-muted-foreground">
                  {commissionStats?.s1.count || 0} транзакций
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">S2 комиссии (всего)</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            {loadingStats ? (
              <Skeleton className="h-7 w-24" />
            ) : (
              <>
                <div className="text-2xl font-bold">
                  {formatMoney(commissionStats?.s2.total || 0)}
                </div>
                <p className="text-xs text-muted-foreground">
                  {commissionStats?.s2.count || 0} транзакций
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Заморожено</CardTitle>
            <TrendingDown className="h-4 w-4 text-amber-500" />
          </CardHeader>
          <CardContent>
            {loadingStats ? (
              <Skeleton className="h-7 w-24" />
            ) : (
              <>
                <div className="text-2xl font-bold text-amber-500">
                  {formatMoney((commissionStats?.s1.frozen || 0) + (commissionStats?.s2.frozen || 0))}
                </div>
                <p className="text-xs text-muted-foreground">
                  Ожидает разморозки
                </p>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Detailed Audit Tabs */}
      <Tabs defaultValue="balance" className="space-y-4">
        <TabsList>
          <TabsTrigger value="balance" className="relative">
            Балансы
            {(balanceIssues?.length || 0) > 0 && (
              <Badge variant="destructive" className="ml-2 h-5 px-1.5">
                {balanceIssues?.length}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="unlock" className="relative">
            Уровни
            {(unlockViolations?.length || 0) > 0 && (
              <Badge variant="destructive" className="ml-2 h-5 px-1.5">
                {unlockViolations?.length}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="marketing" className="relative">
            Маркетинг
            {(marketingFreeIssues?.length || 0) > 0 && (
              <Badge variant="destructive" className="ml-2 h-5 px-1.5">
                {marketingFreeIssues?.length}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="early" className="relative">
            Ранние комиссии
            {(earlyUnlockIssues?.length || 0) > 0 && (
              <Badge variant="destructive" className="ml-2 h-5 px-1.5">
                {earlyUnlockIssues?.length}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="levels">
            По уровням
          </TabsTrigger>
        </TabsList>

        <TabsContent value="balance">
          <Card>
            <CardHeader>
              <CardTitle>Целостность балансов</CardTitle>
              <CardDescription>
                Сравнение расчётного баланса (сумма транзакций) с балансом в профиле
              </CardDescription>
            </CardHeader>
            <CardContent>
              {loadingBalance ? (
                <div className="space-y-2">
                  <Skeleton className="h-10 w-full" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ) : (balanceIssues?.length || 0) === 0 ? (
                <div className="text-center py-8">
                  <CheckCircle className="h-12 w-12 text-green-500 mx-auto mb-4" />
                  <p className="text-lg font-medium">Все балансы корректны</p>
                  <p className="text-muted-foreground">Расхождений не обнаружено</p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Email</TableHead>
                      <TableHead>Тип проблемы</TableHead>
                      <TableHead className="text-right">Доступно</TableHead>
                      <TableHead className="text-right">Заморожено</TableHead>
                      <TableHead className="text-right">Выведено</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {balanceIssues?.map((issue) => (
                      <TableRow key={issue.user_id}>
                        <TableCell className="font-medium">{issue.email}</TableCell>
                        <TableCell>
                          <Badge variant={issue.issue_type === 'negative_balance' ? 'destructive' : 'outline'}>
                            {issue.issue_type === 'negative_balance' ? 'Отрицательный баланс' : issue.issue_type}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <span className={(issue.details.available_cents || 0) < 0 ? 'text-destructive' : ''}>
                            {formatMoney(issue.details.available_cents || 0)}
                          </span>
                        </TableCell>
                        <TableCell className="text-right">
                          {formatMoney(issue.details.frozen_cents || 0)}
                        </TableCell>
                        <TableCell className="text-right">
                          {formatMoney(issue.details.withdrawn_cents || 0)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="unlock">
          <Card>
            <CardHeader className="flex flex-row items-start justify-between">
              <div>
                <CardTitle>Нарушения разблокировки уровней</CardTitle>
                <CardDescription>
                  Комиссии начисленные на уровни, которые ещё не разблокированы
                </CardDescription>
              </div>
              {(unlockViolations?.length || 0) > 0 && userRole === 'superadmin' && (
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => fixViolationsMutation.mutate(true)}
                    disabled={fixViolationsMutation.isPending}
                  >
                    <Wrench className="h-4 w-4 mr-2" />
                    Проверить исправление
                  </Button>
                  {showDryRun && dryRunResult && (
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => fixViolationsMutation.mutate(false)}
                      disabled={fixViolationsMutation.isPending}
                    >
                      Исправить {dryRunResult.violations_count} нарушений
                    </Button>
                  )}
                </div>
              )}
            </CardHeader>
            <CardContent>
              {showDryRun && dryRunResult && (
                <Alert className="mb-4">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertTitle>Предварительный просмотр исправлений</AlertTitle>
                  <AlertDescription>
                    Будет исправлено {dryRunResult.violations_count} нарушений. 
                    Транзакции будут помечены как "failed" и удалены из балансов.
                  </AlertDescription>
                </Alert>
              )}
              {loadingUnlock ? (
                <div className="space-y-2">
                  <Skeleton className="h-10 w-full" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ) : (unlockViolations?.length || 0) === 0 ? (
                <div className="text-center py-8">
                  <CheckCircle className="h-12 w-12 text-green-500 mx-auto mb-4" />
                  <p className="text-lg font-medium">Нарушений не обнаружено</p>
                  <p className="text-muted-foreground">Все уровни разблокированы корректно</p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Пользователь</TableHead>
                      <TableHead>Уровень</TableHead>
                      <TableHead className="text-right">Рефералов</TableHead>
                      <TableHead className="text-right">Требуется</TableHead>
                      <TableHead className="text-right">Нарушений</TableHead>
                      <TableHead className="text-right">Неправ. сумма</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {unlockViolations?.map((v) => (
                      <TableRow key={`${v.user_id}-${v.level}`}>
                        <TableCell>
                          <div>
                            <p className="font-medium">{v.user_name}</p>
                            <p className="text-sm text-muted-foreground">{v.user_email}</p>
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge>Уровень {v.level}</Badge>
                        </TableCell>
                        <TableCell className="text-right">{v.direct_referrals_count}</TableCell>
                        <TableCell className="text-right">{v.required_referrals}</TableCell>
                        <TableCell className="text-right">
                          <Badge variant="destructive">{v.violation_count}</Badge>
                        </TableCell>
                        <TableCell className="text-right text-destructive">
                          {formatMoney(v.total_wrong_amount_cents)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="marketing">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle>Маркетинговые бесплатные комиссии</CardTitle>
                  <CardDescription>
                    Комиссии начисленные за подписки с бесплатным маркетинговым доступом
                  </CardDescription>
                </div>
                {userRole === 'superadmin' && (marketingFreeIssues?.length || 0) > 0 && (
                  <div className="flex gap-2">
                    {!showMarketingDryRun ? (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => fixMarketingViolationsMutation.mutate(true)}
                        disabled={fixMarketingViolationsMutation.isPending}
                      >
                        {fixMarketingViolationsMutation.isPending ? (
                          <RefreshCw className="h-4 w-4 animate-spin mr-2" />
                        ) : (
                          <ShieldAlert className="h-4 w-4 mr-2" />
                        )}
                        Проверить исправление
                      </Button>
                    ) : (
                      <>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setShowMarketingDryRun(false);
                            setMarketingDryRunResult(null);
                          }}
                        >
                          Отмена
                        </Button>
                        <Button
                          variant="destructive"
                          size="sm"
                          onClick={() => fixMarketingViolationsMutation.mutate(false)}
                          disabled={fixMarketingViolationsMutation.isPending}
                        >
                          {fixMarketingViolationsMutation.isPending ? (
                            <RefreshCw className="h-4 w-4 animate-spin mr-2" />
                          ) : (
                            <Wrench className="h-4 w-4 mr-2" />
                          )}
                          Исправить {marketingDryRunResult?.fixed_count} нарушений
                        </Button>
                      </>
                    )}
                  </div>
                )}
              </div>
            </CardHeader>
            <CardContent>
              {showMarketingDryRun && marketingDryRunResult && (
                <Alert className="mb-4">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertTitle>Предварительный просмотр исправлений</AlertTitle>
                  <AlertDescription>
                    Будет исправлено {marketingDryRunResult.fixed_count} нарушений на сумму {formatMoney(marketingDryRunResult.total_amount_cents || 0)}. 
                    Транзакции будут помечены как "failed" и удалены из балансов.
                  </AlertDescription>
                </Alert>
              )}
              {loadingMarketing ? (
                <div className="space-y-2">
                  <Skeleton className="h-10 w-full" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ) : (marketingFreeIssues?.length || 0) === 0 ? (
                <div className="text-center py-8">
                  <CheckCircle className="h-12 w-12 text-green-500 mx-auto mb-4" />
                  <p className="text-lg font-medium">Аномалий не обнаружено</p>
                  <p className="text-muted-foreground">Маркетинговые комиссии корректны</p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Получатель</TableHead>
                      <TableHead>Подписчик</TableHead>
                      <TableHead>Проблема</TableHead>
                      <TableHead className="text-right">Сумма</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {marketingFreeIssues?.map((issue) => (
                      <TableRow key={issue.transaction_id}>
                        <TableCell className="font-medium">{issue.user_email}</TableCell>
                        <TableCell>{issue.subscriber_name}</TableCell>
                        <TableCell>
                          <Badge variant="outline">{issue.issue}</Badge>
                        </TableCell>
                        <TableCell className="text-right text-destructive">
                          {formatMoney(issue.amount_cents)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="early">
          <Card>
            <CardHeader className="flex flex-row items-start justify-between">
              <div>
                <CardTitle>Ранние комиссии (до разблокировки уровня)</CardTitle>
                <CardDescription>
                  Комиссии начисленные на уровни, которые ещё не были разблокированы на момент активации подписки
                </CardDescription>
              </div>
              {(earlyUnlockIssues?.length || 0) > 0 && userRole === 'superadmin' && (
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => fixEarlyViolationsMutation.mutate(true)}
                    disabled={fixEarlyViolationsMutation.isPending}
                  >
                    {fixEarlyViolationsMutation.isPending ? (
                      <RefreshCw className="h-4 w-4 animate-spin mr-2" />
                    ) : (
                      <Wrench className="h-4 w-4 mr-2" />
                    )}
                    Проверить исправление
                  </Button>
                  {showEarlyDryRun && earlyDryRunResult && (
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => fixEarlyViolationsMutation.mutate(false)}
                      disabled={fixEarlyViolationsMutation.isPending}
                    >
                      Исправить {earlyDryRunResult.violations_found} нарушений
                    </Button>
                  )}
                </div>
              )}
            </CardHeader>
            <CardContent>
              {showEarlyDryRun && earlyDryRunResult && (
                <Alert className="mb-4">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertTitle>Предварительный просмотр исправлений</AlertTitle>
                  <AlertDescription>
                    Найдено {earlyDryRunResult.violations_found} комиссий на сумму {formatMoney(earlyDryRunResult.total_amount_cents || 0)}, 
                    начисленных до того, как спонсор разблокировал соответствующий уровень.
                  </AlertDescription>
                </Alert>
              )}
              {loadingEarly ? (
                <div className="space-y-2">
                  <Skeleton className="h-10 w-full" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ) : (earlyUnlockIssues?.length || 0) === 0 ? (
                <div className="text-center py-8">
                  <CheckCircle className="h-12 w-12 text-green-500 mx-auto mb-4" />
                  <p className="text-lg font-medium">Ранних комиссий не обнаружено</p>
                  <p className="text-muted-foreground">Все комиссии начислены после разблокировки уровней</p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Получатель</TableHead>
                      <TableHead>Уровень</TableHead>
                      <TableHead>Подписчик</TableHead>
                      <TableHead>Дата подписки</TableHead>
                      <TableHead className="text-right">Было / Нужно</TableHead>
                      <TableHead className="text-right">Сумма</TableHead>
                      <TableHead>Статус</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {earlyUnlockIssues?.map((issue) => (
                      <TableRow key={issue.transaction_id}>
                        <TableCell className="font-medium">{issue.user_name}</TableCell>
                        <TableCell>
                          <Badge variant="outline">
                            {issue.structure_type === 'primary' ? 'S1' : 'S2'} Ур. {issue.level}
                          </Badge>
                        </TableCell>
                        <TableCell>{issue.subscriber_name}</TableCell>
                        <TableCell>
                          {format(new Date(issue.subscription_paid_at), 'dd.MM.yyyy HH:mm', { locale: ru })}
                        </TableCell>
                        <TableCell className="text-right">
                          <span className="text-destructive">{issue.actual_referrals_at_time}</span>
                          {' / '}
                          <span className="text-muted-foreground">{issue.required_referrals}</span>
                        </TableCell>
                        <TableCell className="text-right text-destructive">
                          {formatMoney(issue.amount_cents)}
                        </TableCell>
                        <TableCell>
                          <Badge variant={issue.status === 'frozen' ? 'secondary' : 'default'}>
                            {issue.status === 'frozen' ? 'Заморожена' : 'Выплачена'}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="levels">
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>S1 по уровням (Абонентская)</CardTitle>
                <CardDescription>10% на каждом из 5 уровней</CardDescription>
              </CardHeader>
              <CardContent>
                {loadingStats ? (
                  <div className="space-y-2">
                    {[1, 2, 3, 4, 5].map((i) => (
                      <Skeleton key={i} className="h-8 w-full" />
                    ))}
                  </div>
                ) : (
                  <div className="space-y-3">
                    {[1, 2, 3, 4, 5].map((level) => (
                      <div key={level} className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <Badge variant="outline">Ур. {level}</Badge>
                          <span className="text-sm text-muted-foreground">10%</span>
                        </div>
                        <span className="font-medium">
                          {formatMoney(commissionStats?.s1.byLevel[level] || 0)}
                        </span>
                      </div>
                    ))}
                    <div className="border-t pt-3 flex items-center justify-between font-bold">
                      <span>Итого S1:</span>
                      <span>{formatMoney(commissionStats?.s1.total || 0)}</span>
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>S2 по уровням (Товарная)</CardTitle>
                <CardDescription>Проценты согласно MLM правилам</CardDescription>
              </CardHeader>
              <CardContent>
                {loadingStats ? (
                  <div className="space-y-2">
                    {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((i) => (
                      <Skeleton key={i} className="h-8 w-full" />
                    ))}
                  </div>
                ) : (
                  <div className="space-y-3">
                    {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((level) => {
                      const amount = commissionStats?.s2.byLevel[level] || 0;
                      if (amount === 0) return null;
                      return (
                        <div key={level} className="flex items-center justify-between">
                          <Badge variant="outline">Ур. {level}</Badge>
                          <span className="font-medium">
                            {formatMoney(amount)}
                          </span>
                        </div>
                      );
                    })}
                    <div className="border-t pt-3 flex items-center justify-between font-bold">
                      <span>Итого S2:</span>
                      <span>{formatMoney(commissionStats?.s2.total || 0)}</span>
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  );
}
