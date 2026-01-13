import { useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { 
  useSponsorsWithMissingCommissions, 
  useBackfillSponsorCommissions,
  useBackfillAllCommissions 
} from "@/hooks/useCommissionBackfill";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { 
  AlertTriangle, 
  CheckCircle, 
  Play, 
  RefreshCw, 
  Search,
  Zap
} from "lucide-react";
import { formatMoney } from "@/utils/formatMoney";

export default function CommissionBackfill() {
  const { userRole } = useAuth();
  const { data: sponsors, isLoading, refetch } = useSponsorsWithMissingCommissions();
  const backfillSponsor = useBackfillSponsorCommissions();
  const backfillAll = useBackfillAllCommissions();
  
  const [selectedSponsor, setSelectedSponsor] = useState<{
    id: string;
    name: string;
    missing: number;
    amount: number;
  } | null>(null);
  const [dryRunResult, setDryRunResult] = useState<any>(null);
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);
  const [showAllConfirmDialog, setShowAllConfirmDialog] = useState(false);
  const [allDryRunResult, setAllDryRunResult] = useState<any>(null);

  if (userRole !== 'admin' && userRole !== 'superadmin') {
    return (
      <div className="p-6">
        <Card className="border-destructive">
          <CardContent className="pt-6">
            <p className="text-destructive">Доступ запрещён. Требуются права администратора.</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  const totalMissing = sponsors?.reduce((sum, s) => sum + s.missing_count, 0) || 0;
  const totalAmount = sponsors?.reduce((sum, s) => sum + s.missing_amount_kzt, 0) || 0;

  const handleDryRun = async (sponsorId: string, name: string, missing: number, amount: number) => {
    setSelectedSponsor({ id: sponsorId, name, missing, amount });
    try {
      const result = await backfillSponsor.mutateAsync({ sponsorId, dryRun: true });
      setDryRunResult(result);
      setShowConfirmDialog(true);
    } catch (error) {
      console.error('Dry run failed:', error);
    }
  };

  const handleConfirmBackfill = async () => {
    if (!selectedSponsor) return;
    try {
      await backfillSponsor.mutateAsync({ sponsorId: selectedSponsor.id, dryRun: false });
      setShowConfirmDialog(false);
      setSelectedSponsor(null);
      setDryRunResult(null);
      refetch();
    } catch (error) {
      console.error('Backfill failed:', error);
    }
  };

  const handleAllDryRun = async () => {
    try {
      const result = await backfillAll.mutateAsync({ dryRun: true });
      setAllDryRunResult(result);
      setShowAllConfirmDialog(true);
    } catch (error) {
      console.error('All dry run failed:', error);
    }
  };

  const handleConfirmAllBackfill = async () => {
    try {
      await backfillAll.mutateAsync({ dryRun: false });
      setShowAllConfirmDialog(false);
      setAllDryRunResult(null);
      refetch();
    } catch (error) {
      console.error('All backfill failed:', error);
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Доначисление комиссий S1</h1>
          <p className="text-muted-foreground">
            Поиск и восстановление пропущенных комиссий первого уровня
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => refetch()} disabled={isLoading}>
            <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
            Обновить
          </Button>
          {userRole === 'superadmin' && totalMissing > 0 && (
            <Button 
              variant="destructive" 
              onClick={handleAllDryRun}
              disabled={backfillAll.isPending}
            >
              <Zap className="h-4 w-4 mr-2" />
              Доначислить все ({totalMissing})
            </Button>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader className="pb-2">
            <CardDescription>Спонсоров с пропусками</CardDescription>
            <CardTitle className="text-3xl">{sponsors?.length || 0}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardDescription>Всего пропущено комиссий</CardDescription>
            <CardTitle className="text-3xl text-destructive">{totalMissing}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardDescription>Сумма к доначислению</CardDescription>
            <CardTitle className="text-3xl text-primary">
              {formatMoney(totalAmount)}
            </CardTitle>
          </CardHeader>
        </Card>
      </div>

      {/* Sponsors Table */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Search className="h-5 w-5" />
            Спонсоры с пропущенными комиссиями
          </CardTitle>
          <CardDescription>
            Список пользователей, которые не получили комиссии за подписки своих партнёров
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-2">
              {[1, 2, 3].map(i => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : sponsors?.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <CheckCircle className="h-12 w-12 text-green-500 mb-4" />
              <p className="text-lg font-medium">Все комиссии начислены корректно</p>
              <p className="text-muted-foreground">Пропущенных комиссий не найдено</p>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Спонсор</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead className="text-center">Пропущено</TableHead>
                  <TableHead className="text-center">Партнёров</TableHead>
                  <TableHead className="text-right">Сумма</TableHead>
                  <TableHead className="text-right">Действия</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sponsors?.map((sponsor) => (
                  <TableRow key={sponsor.sponsor_id}>
                    <TableCell className="font-medium">
                      {sponsor.sponsor_name || 'Без имени'}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {sponsor.sponsor_email}
                    </TableCell>
                    <TableCell className="text-center">
                      <Badge variant="destructive">{sponsor.missing_count}</Badge>
                    </TableCell>
                    <TableCell className="text-center">
                      {sponsor.partners_count}
                    </TableCell>
                    <TableCell className="text-right font-medium">
                      {formatMoney(sponsor.missing_amount_kzt)}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => handleDryRun(
                          sponsor.sponsor_id, 
                          sponsor.sponsor_name || sponsor.sponsor_email,
                          sponsor.missing_count,
                          sponsor.missing_amount_kzt
                        )}
                        disabled={backfillSponsor.isPending}
                      >
                        <Play className="h-4 w-4 mr-1" />
                        Проверить
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Single Sponsor Confirm Dialog */}
      <Dialog open={showConfirmDialog} onOpenChange={setShowConfirmDialog}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-yellow-500" />
              Подтверждение доначисления
            </DialogTitle>
            <DialogDescription>
              Вы собираетесь доначислить комиссии для {selectedSponsor?.name}
            </DialogDescription>
          </DialogHeader>

          {dryRunResult && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="bg-muted p-3 rounded-lg">
                  <p className="text-muted-foreground">Подписок обработано</p>
                  <p className="text-xl font-bold">{dryRunResult.subscriptions_processed}</p>
                </div>
                <div className="bg-muted p-3 rounded-lg">
                  <p className="text-muted-foreground">Комиссий к созданию</p>
                  <p className="text-xl font-bold text-primary">{dryRunResult.commissions_created}</p>
                </div>
              </div>
              
              <div className="bg-primary/10 p-4 rounded-lg">
                <p className="text-sm text-muted-foreground">Сумма к начислению</p>
                <p className="text-2xl font-bold text-primary">
                  {formatMoney(dryRunResult.total_kzt || 0)}
                </p>
              </div>

              {dryRunResult.commissions_skipped > 0 && (
                <p className="text-sm text-muted-foreground">
                  Пропущено (уже существуют): {dryRunResult.commissions_skipped}
                </p>
              )}
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowConfirmDialog(false)}>
              Отмена
            </Button>
            <Button 
              onClick={handleConfirmBackfill}
              disabled={backfillSponsor.isPending || !dryRunResult?.commissions_created}
            >
              {backfillSponsor.isPending ? (
                <>
                  <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                  Начисление...
                </>
              ) : (
                <>
                  <CheckCircle className="h-4 w-4 mr-2" />
                  Подтвердить ({dryRunResult?.commissions_created || 0} комиссий)
                </>
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* All Sponsors Confirm Dialog */}
      <Dialog open={showAllConfirmDialog} onOpenChange={setShowAllConfirmDialog}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Zap className="h-5 w-5 text-yellow-500" />
              Массовое доначисление комиссий
            </DialogTitle>
            <DialogDescription>
              Вы собираетесь доначислить ВСЕ пропущенные комиссии S1
            </DialogDescription>
          </DialogHeader>

          {allDryRunResult && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="bg-muted p-3 rounded-lg">
                  <p className="text-muted-foreground">Подписок обработано</p>
                  <p className="text-xl font-bold">{allDryRunResult.subscriptions_processed}</p>
                </div>
                <div className="bg-muted p-3 rounded-lg">
                  <p className="text-muted-foreground">Комиссий к созданию</p>
                  <p className="text-xl font-bold text-primary">{allDryRunResult.commissions_created}</p>
                </div>
              </div>
              
              <div className="bg-destructive/10 border border-destructive/20 p-4 rounded-lg">
                <p className="text-sm text-muted-foreground">Общая сумма к начислению</p>
                <p className="text-2xl font-bold text-destructive">
                  {formatMoney(allDryRunResult.total_kzt || 0)}
                </p>
              </div>

              <div className="bg-yellow-500/10 border border-yellow-500/20 p-3 rounded-lg">
                <p className="text-sm text-yellow-700 dark:text-yellow-400">
                  ⚠️ Это действие нельзя отменить. Убедитесь, что данные корректны.
                </p>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAllConfirmDialog(false)}>
              Отмена
            </Button>
            <Button 
              variant="destructive"
              onClick={handleConfirmAllBackfill}
              disabled={backfillAll.isPending || !allDryRunResult?.commissions_created}
            >
              {backfillAll.isPending ? (
                <>
                  <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
                  Начисление...
                </>
              ) : (
                <>
                  <Zap className="h-4 w-4 mr-2" />
                  Доначислить все ({allDryRunResult?.commissions_created || 0})
                </>
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
