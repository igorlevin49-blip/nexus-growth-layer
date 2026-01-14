import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Skeleton } from "@/components/ui/skeleton";
import { AlertTriangle, CheckCircle, XCircle, RefreshCw, TrendingDown, TrendingUp, Minus } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface UserCommissionAuditDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  userName: string | null;
}

interface CommissionAuditRow {
  partner_id: string;
  partner_name: string | null;
  partner_email: string | null;
  level: number;
  subscription_id: string | null;
  subscription_amount_kzt: number | null;
  commission_received: boolean;
  commission_amount_kzt: number | null;  // Сумма в целых тенге
  expected_percent: number | null;
  expected_commission_kzt: number | null;  // Ожидаемая комиссия в целых тенге
  actual_vs_expected: string;
  no_commission_reason: string | null;
}

const getReasonText = (reason: string | null): string => {
  switch (reason) {
    case 'subscription_not_active':
      return 'Подписка не активна';
    case 'too_deep':
      return 'Глубже 5 уровня';
    case 'sponsor_inactive':
      return 'Спонсор был неактивен';
    case 'unknown':
      return 'Неизвестно';
    default:
      return reason || '-';
  }
};

const getStatusBadge = (status: string) => {
  switch (status) {
    case 'OK':
      return <Badge className="bg-success text-success-foreground gap-1"><CheckCircle className="h-3 w-3" />OK</Badge>;
    case 'MISSING':
      return <Badge variant="destructive" className="gap-1"><XCircle className="h-3 w-3" />Нет</Badge>;
    case 'UNDERPAID':
      return <Badge className="bg-orange-500 text-white gap-1"><TrendingDown className="h-3 w-3" />Недоплата</Badge>;
    case 'OVERPAID':
      return <Badge className="bg-blue-500 text-white gap-1"><TrendingUp className="h-3 w-3" />Переплата</Badge>;
    default:
      return <Badge variant="secondary"><Minus className="h-3 w-3" /></Badge>;
  }
};

export function UserCommissionAuditDialog({ 
  open, 
  onOpenChange, 
  userId, 
  userName 
}: UserCommissionAuditDialogProps) {
  const [isRecalculating, setIsRecalculating] = useState(false);

  const { data: auditData, isLoading, refetch } = useQuery({
    queryKey: ['admin-commission-audit', userId],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('admin_audit_user_commissions', {
        p_admin_id: user.id,
        p_user_id: userId
      });

      if (error) throw error;
      // Маппим результат API к нашему интерфейсу
      return (data || []).map((row: any) => ({
        ...row,
        commission_amount_kzt: row.commission_amount_kzt ?? row.commission_amount_cents ?? 0,
        expected_commission_kzt: row.expected_commission_kzt ?? row.expected_commission_cents ?? 0,
      })) as CommissionAuditRow[];
    },
    enabled: open && !!userId,
  });

  // Calculate summary stats
  const stats = {
    total: auditData?.length || 0,
    ok: auditData?.filter(r => r.actual_vs_expected === 'OK').length || 0,
    missing: auditData?.filter(r => r.actual_vs_expected === 'MISSING').length || 0,
    underpaid: auditData?.filter(r => r.actual_vs_expected === 'UNDERPAID').length || 0,
    overpaid: auditData?.filter(r => r.actual_vs_expected === 'OVERPAID').length || 0,
    totalExpected: auditData?.reduce((sum, r) => sum + (r.expected_commission_kzt || 0), 0) || 0,
    totalActual: auditData?.reduce((sum, r) => sum + (r.commission_amount_kzt || 0), 0) || 0,
  };

  const handleRecalculateS1 = async () => {
    setIsRecalculating(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Сначала делаем dry run чтобы показать что будет изменено
      const { data: dryRunData, error: dryRunError } = await supabase.rpc('backfill_missing_multilevel_commissions', {
        p_admin_id: user.id,
        p_dry_run: true,
        p_target_user_id: userId
      });

      if (dryRunError) throw dryRunError;
      
      const dryResult = dryRunData as any;
      
      // Если нечего создавать - сообщаем
      if (!dryResult?.commissions_created && dryResult?.commissions_created !== 0) {
        // Попробуем альтернативную функцию backfill_missing_s1_commissions
        const { data: altData, error: altError } = await supabase.rpc('backfill_missing_s1_commissions', {
          p_admin_id: user.id,
          p_dry_run: false,
          p_sponsor_id: userId
        });

        if (altError) throw altError;

        const altResult = altData as any;
        toast.success('Комиссии S1 пересчитаны', {
          description: `Создано: ${altResult?.commissions_created || 0}, Пропущено: ${altResult?.commissions_skipped || 0}`
        });
        refetch();
        return;
      }

      if (dryResult.commissions_created === 0) {
        toast.info('Нет комиссий для доначисления', {
          description: 'Все комиссии уже начислены корректно'
        });
        refetch();
        return;
      }

      // Если есть что создавать - выполняем реальный backfill
      const { data, error } = await supabase.rpc('backfill_missing_multilevel_commissions', {
        p_admin_id: user.id,
        p_dry_run: false,
        p_target_user_id: userId
      });

      if (error) throw error;

      const result = data as any;
      toast.success('Комиссии S1 пересчитаны', {
        description: `Создано: ${result?.commissions_created || 0}, Пропущено: ${result?.commissions_skipped || 0}, Сумма: ${(result?.total_kzt || 0).toLocaleString()} ₸`
      });
      refetch();
    } catch (error: any) {
      console.error('Error recalculating commissions:', error);
      toast.error('Ошибка пересчёта', { 
        description: error.message || 'Неизвестная ошибка'
      });
    } finally {
      setIsRecalculating(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-orange-500" />
            Аудит комиссий S1: {userName || userId.substring(0, 8)}
          </DialogTitle>
        </DialogHeader>

        {/* Summary stats */}
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-4">
          <div className="p-3 bg-muted rounded-lg text-center">
            <div className="text-2xl font-bold">{stats.total}</div>
            <div className="text-xs text-muted-foreground">Всего партнёров</div>
          </div>
          <div className="p-3 bg-success/10 rounded-lg text-center">
            <div className="text-2xl font-bold text-success">{stats.ok}</div>
            <div className="text-xs text-muted-foreground">Корректно</div>
          </div>
          <div className="p-3 bg-destructive/10 rounded-lg text-center">
            <div className="text-2xl font-bold text-destructive">{stats.missing}</div>
            <div className="text-xs text-muted-foreground">Отсутствуют</div>
          </div>
          <div className="p-3 bg-orange-500/10 rounded-lg text-center">
            <div className="text-2xl font-bold text-orange-500">{stats.underpaid}</div>
            <div className="text-xs text-muted-foreground">Недоплата</div>
          </div>
          <div className="p-3 bg-blue-500/10 rounded-lg text-center">
            <div className="text-2xl font-bold text-blue-500">{stats.overpaid}</div>
            <div className="text-xs text-muted-foreground">Переплата</div>
          </div>
        </div>

        {/* Totals comparison */}
        <div className="flex items-center justify-between p-3 bg-muted/50 rounded-lg mb-4">
          <div>
            <span className="text-sm text-muted-foreground">Ожидаемая сумма:</span>
            <span className="ml-2 font-medium">{stats.totalExpected.toLocaleString('ru-RU')} ₸</span>
          </div>
          <div>
            <span className="text-sm text-muted-foreground">Фактическая сумма:</span>
            <span className="ml-2 font-medium">{stats.totalActual.toLocaleString('ru-RU')} ₸</span>
          </div>
          <div>
            <span className="text-sm text-muted-foreground">Разница:</span>
            <span className={`ml-2 font-medium ${stats.totalActual - stats.totalExpected < 0 ? 'text-destructive' : 'text-success'}`}>
              {(stats.totalActual - stats.totalExpected).toLocaleString('ru-RU')} ₸
            </span>
          </div>
          <Button 
            variant="outline" 
            size="sm" 
            onClick={handleRecalculateS1}
            disabled={isRecalculating}
          >
            <RefreshCw className={`h-4 w-4 mr-2 ${isRecalculating ? 'animate-spin' : ''}`} />
            Пересчитать S1
          </Button>
        </div>

        {/* Audit table */}
        {isLoading ? (
          <div className="space-y-2">
            {[...Array(5)].map((_, i) => <Skeleton key={i} className="h-12" />)}
          </div>
        ) : auditData && auditData.length > 0 ? (
          <div className="border rounded-lg overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Партнёр</TableHead>
                  <TableHead className="text-center">Уровень</TableHead>
                  <TableHead className="text-right">Подписка</TableHead>
                  <TableHead className="text-center">%</TableHead>
                  <TableHead className="text-right">Ожидаемая</TableHead>
                  <TableHead className="text-right">Фактическая</TableHead>
                  <TableHead className="text-center">Статус</TableHead>
                  <TableHead>Причина</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {auditData.map((row) => (
                  <TableRow 
                    key={row.partner_id + (row.subscription_id || '')}
                    className={row.actual_vs_expected === 'MISSING' || row.actual_vs_expected === 'UNDERPAID' ? 'bg-destructive/5' : ''}
                  >
                    <TableCell>
                      <div>
                        <div className="font-medium">{row.partner_name || 'Без имени'}</div>
                        <div className="text-xs text-muted-foreground">{row.partner_email}</div>
                      </div>
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant="outline">L{row.level}</Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      {row.subscription_amount_kzt?.toLocaleString('ru-RU')} ₸
                    </TableCell>
                    <TableCell className="text-center">
                      {row.expected_percent || 0}%
                    </TableCell>
                    <TableCell className="text-right">
                      {(row.expected_commission_kzt || 0).toLocaleString('ru-RU')} ₸
                    </TableCell>
                    <TableCell className="text-right">
                      {row.commission_received 
                        ? `${(row.commission_amount_kzt || 0).toLocaleString('ru-RU')} ₸`
                        : '-'
                      }
                    </TableCell>
                    <TableCell className="text-center">
                      {getStatusBadge(row.actual_vs_expected)}
                    </TableCell>
                    <TableCell>
                      {row.no_commission_reason && (
                        <span className="text-xs text-muted-foreground">
                          {getReasonText(row.no_commission_reason)}
                        </span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        ) : (
          <div className="text-center py-8 text-muted-foreground">
            <AlertTriangle className="h-12 w-12 mx-auto mb-4 opacity-50" />
            <p>Нет данных для аудита</p>
            <p className="text-sm">У пользователя нет партнёров с активными подписками</p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
