import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { Ban, CheckCircle, XCircle, Trash2, RotateCcw, UserPlus, Network, Search, Archive, AlertTriangle, ShieldOff, Copy } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { useSoftDeleteUser, useRestoreUser, useHardDeleteUser } from "@/hooks/useCleanupTestData";
import { useBanUser, useReassignReferrals } from "@/hooks/useBanUser";
import { BindSponsorDialog } from "@/components/Admin/BindSponsorDialog";
import { UserNetworkDialog } from "@/components/Admin/UserNetworkDialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { useAuth } from "@/hooks/useAuth";
import { getReferralLink } from "@/config/constants";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Alert, AlertDescription } from "@/components/ui/alert";

interface Profile {
  id: string;
  full_name: string | null;
  email: string | null;
  referral_code: string;
  phone: string | null;
  subscription_status: string;
  balance: number;
  created_at: string;
  is_active: boolean;
  deleted_at: string | null;
  is_archived: boolean;
  monthly_activation_completed: boolean;
  sponsor_id: string | null;
  referrer_snapshot: any;
  sponsor?: {
    full_name: string | null;
    email: string | null;
    is_active: boolean;
    deleted_at: string | null;
    is_archived: boolean;
  } | null;
  realBalance?: number;
}

interface DeleteDialogState {
  open: boolean;
  userId: string;
  userName: string;
  userEmail: string;
  referralsCount: number;
  mode: 'archive' | 'hard_delete';
  reassignReferrals: boolean;
  upperSponsorId: string | null;
}

export default function AdminUsers() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [showArchived, setShowArchived] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [bindSponsorDialog, setBindSponsorDialog] = useState<{ open: boolean; userId: string; userName: string }>({
    open: false,
    userId: "",
    userName: ""
  });
  const [networkDialog, setNetworkDialog] = useState<{ 
    open: boolean; 
    userId: string; 
    userName: string; 
    userEmail: string;
  }>({
    open: false,
    userId: "",
    userName: "",
    userEmail: ""
  });
  const [deleteDialog, setDeleteDialog] = useState<DeleteDialogState>({
    open: false,
    userId: "",
    userName: "",
    userEmail: "",
    referralsCount: 0,
    mode: 'archive',
    reassignReferrals: false,
    upperSponsorId: null
  });

  const softDeleteUser = useSoftDeleteUser();
  const hardDeleteUser = useHardDeleteUser();
  const restoreUser = useRestoreUser();
  const banUser = useBanUser();
  const reassignReferrals = useReassignReferrals();

  useEffect(() => {
    fetchProfiles();
  }, [showArchived, searchQuery]);

  const fetchProfiles = async () => {
    try {
      let query = supabase
        .from('profiles')
        .select(`
          *,
          sponsor:sponsor_id(full_name, email, is_active, deleted_at, is_archived)
        `);

      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      if (searchQuery.trim()) {
        const search = searchQuery.trim();
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        let orConditions = [
          `email.ilike.%${search}%`,
          `full_name.ilike.%${search}%`,
          `referral_code.ilike.%${search}%`
        ];
        
        if (isValidUuid) {
          orConditions.push(`id.eq.${search}`);
        }
        
        query = query.or(orConditions.join(','));
      }

      const { data, error } = await query.order('created_at', { ascending: false });

      if (error) throw error;
      
      const { data: balancesData } = await supabase.rpc('get_all_user_balances');
      const balancesMap = new Map<string, number>();
      (balancesData || []).forEach((b: any) => {
        const available = Number(b?.available_kzt ?? b?.available_cents ?? 0);
        const frozen = Number(b?.frozen_kzt ?? b?.frozen_cents ?? 0);
        const pending = Number(b?.pending_kzt ?? b?.pending_cents ?? 0);
        balancesMap.set(b.user_id, available + frozen + pending);
      });
      
      const profilesWithBalances = (data || []).map(profile => ({
        ...profile,
        realBalance: balancesMap.get(profile.id) ?? 0
      }));
      
      setProfiles(profilesWithBalances);
    } catch (error) {
      console.error('Error fetching profiles:', error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить пользователей",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const copyUserReferralLink = async (refCode?: string | null) => {
    if (!refCode) return;
    try {
      await navigator.clipboard.writeText(getReferralLink(refCode));
      toast({
        title: "Скопировано",
        description: "Реферальная ссылка скопирована",
      });
    } catch (e) {
      console.error('Copy referral link error:', e);
      toast({
        title: "Ошибка",
        description: "Не удалось скопировать ссылку",
        variant: "destructive",
      });
    }
  };

  const runDiagnose = async () => {
    try {
      const { data, error } = await supabase.rpc('admin_referral_diagnose');
      if (error) throw error;
      const total = data?.length || 0;
      const noSponsor = (data || []).filter((d: any) => d.issue === 'no_sponsor_and_no_referral').length;
      const missingRef = (data || []).filter((d: any) => d.issue === 'missing_referral_row').length;
      toast({
        title: 'Диагностика завершена',
        description: `Найдено проблем: ${total}. Без спонсора: ${noSponsor}. Без записи referrals: ${missingRef}.`,
      });
    } catch (e:any) {
      console.error('Diagnose error', e);
      toast({ title: 'Ошибка', description: 'Не удалось выполнить диагностику', variant: 'destructive' });
    }
  };

  const runBackfill = async () => {
    try {
      const { data, error } = await (supabase.rpc as any)('admin_backfill_sponsor_from_metadata');
      if (error) throw error;
      
      const result = data as { success: boolean; updated_count: number; inserted_referrals: number; failed_count: number };
      
      if (result.success) {
        toast({
          title: 'Связи восстановлены',
          description: `Обновлено: ${result.updated_count}, не найдено: ${result.failed_count}`,
        });
      } else {
        toast({
          title: 'Предупреждение',
          description: 'Восстановление завершено с предупреждениями',
        });
      }
      
      fetchProfiles();
    } catch (error: any) {
      console.error('Backfill error:', error);
      toast({
        title: 'Ошибка',
        description: error.message || "Ошибка при восстановлении связей",
        variant: 'destructive',
      });
    }
  };

  const [isRecalculating, setIsRecalculating] = useState(false);

  const runRecalculateCommissions = async () => {
    setIsRecalculating(true);
    try {
      const { data, error } = await supabase.rpc('admin_recalculate_commissions' as any);
      
      if (error) throw error;
      
      const result = data as any;
      if (result && result.length > 0) {
        const r = result[0];
        toast({
          title: 'Пересчет комиссий завершен',
          description: `Подписки: ${r.recalculated_subscriptions} | Заказы: ${r.recalculated_orders} | Всего комиссий: ${r.total_commissions_created}`,
        });
        console.log('Детали пересчета:', r.details);
      } else {
        toast({
          title: 'Пересчет завершен',
          description: 'Нет комиссий для пересчета',
        });
      }
      fetchProfiles();
    } catch (error: any) {
      console.error('Recalculate error:', error);
      toast({ 
        title: 'Ошибка', 
        description: `Не удалось пересчитать комиссии: ${error.message}`, 
        variant: 'destructive' 
      });
    } finally {
      setIsRecalculating(false);
    }
  };

  const handleBanUser = async (userId: string, currentStatus: string) => {
    const action = currentStatus === 'frozen' ? 'unban' : 'ban';
    await banUser.mutateAsync({ userId, action });
    fetchProfiles();
  };

  const openDeleteDialog = async (
    userId: string, 
    userName: string, 
    userEmail: string,
    sponsorId: string | null,
    mode: 'archive' | 'hard_delete'
  ) => {
    // Count referrals
    const { count } = await supabase
      .from('profiles')
      .select('*', { count: 'exact', head: true })
      .eq('sponsor_id', userId);
    
    setDeleteDialog({
      open: true,
      userId,
      userName,
      userEmail,
      referralsCount: count || 0,
      mode,
      reassignReferrals: false,
      upperSponsorId: sponsorId
    });
  };

  const handleConfirmDelete = async () => {
    const { userId, mode, reassignReferrals: shouldReassign } = deleteDialog;
    
    try {
      // If reassign is checked and there are referrals, reassign first
      if (shouldReassign && deleteDialog.referralsCount > 0) {
        await reassignReferrals.mutateAsync(userId);
      }
      
      // Then delete
      if (mode === 'archive') {
        await softDeleteUser.mutateAsync(userId);
      } else {
        await hardDeleteUser.mutateAsync(userId);
      }
      
      setDeleteDialog({ ...deleteDialog, open: false });
      fetchProfiles();
    } catch (error) {
      console.error('Delete error:', error);
    }
  };

  const handleRestoreUser = async (userId: string) => {
    await restoreUser.mutateAsync(userId);
    fetchProfiles();
  };

  if (loading) {
    return (
      <div className="p-8">
        <Card>
          <CardHeader>
            <Skeleton className="h-8 w-64" />
          </CardHeader>
          <CardContent className="space-y-4">
            <Skeleton className="h-10 w-full" />
            <div className="space-y-3">
              {[1, 2, 3, 4, 5, 6].map((i) => <Skeleton key={i} className="h-16 w-full" />)}
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-8">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Управление пользователями</CardTitle>
          <div className="flex items-center gap-2">
            {isSuperAdmin && (
              <>
                <Button onClick={runDiagnose} variant="outline" size="sm">
                  Диагностика
                </Button>
                <Button onClick={runBackfill} variant="outline" size="sm">
                  Восстановить связи
                </Button>
                <Button
                  onClick={runRecalculateCommissions}
                  disabled={isRecalculating}
                  variant="outline"
                  size="sm"
                >
                  {isRecalculating ? "Пересчитываем..." : "Пересчитать комиссии"}
                </Button>
              </>
            )}
            <label className="flex items-center gap-2 text-sm">
              <input 
                type="checkbox" 
                checked={showArchived}
                onChange={(e) => setShowArchived(e.target.checked)}
                className="rounded"
              />
              Показывать архивных
            </label>
          </div>
        </CardHeader>
        <CardContent>
          {/* Search Bar */}
          <div className="mb-4 flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Поиск по email, имени, ID или реф.коду..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>

          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Имя</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Реф. ссылка</TableHead>
                <TableHead>Телефон</TableHead>
                <TableHead>Пригласивший</TableHead>
                <TableHead>Статус аккаунта</TableHead>
                <TableHead>Статус подписки</TableHead>
                <TableHead>Активация</TableHead>
                <TableHead>Баланс (KZT)</TableHead>
                <TableHead>Дата регистрации</TableHead>
                <TableHead className="text-right">Действия</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {profiles.map((profile) => (
                <TableRow key={profile.id} className={profile.deleted_at ? 'opacity-50' : ''}>
                  <TableCell>{profile.full_name || 'Не указано'}</TableCell>
                  <TableCell>{profile.email}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <code className="text-xs bg-muted px-2 py-1 rounded">
                        {profile.referral_code || '—'}
                      </code>
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => copyUserReferralLink(profile.referral_code)}
                        disabled={!profile.referral_code}
                        title="Скопировать реферальную ссылку"
                      >
                        <Copy className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                  <TableCell>{profile.phone || '—'}</TableCell>
                  <TableCell>
                    {(() => {
                      const sponsorIsDeleted = profile.sponsor?.deleted_at || profile.sponsor?.is_archived || !profile.sponsor?.is_active;
                      
                      if (profile.sponsor && !sponsorIsDeleted) {
                        return (
                          <div className="text-sm">
                            <div className="font-medium">{profile.sponsor.full_name || 'Не указано'}</div>
                            <div className="text-muted-foreground">{profile.sponsor.email}</div>
                          </div>
                        );
                      } else if (profile.referrer_snapshot) {
                        return (
                          <div className="text-sm">
                            <div className="font-medium">{profile.referrer_snapshot.full_name || 'Не указано'}</div>
                            <div className="text-muted-foreground">{profile.referrer_snapshot.email}</div>
                            <Badge variant="secondary" className="mt-1">архив</Badge>
                          </div>
                        );
                      } else if (profile.sponsor_id) {
                        return (
                          <div className="text-sm">
                            <div className="text-muted-foreground">Данные недоступны</div>
                            <Badge variant="secondary" className="mt-1">архив</Badge>
                          </div>
                        );
                      } else {
                        return <span className="text-muted-foreground">—</span>;
                      }
                    })()}
                  </TableCell>
                  <TableCell>
                    <Badge 
                      variant={
                        profile.is_active && !profile.deleted_at && !profile.is_archived
                          ? 'default' 
                          : profile.subscription_status === 'frozen'
                          ? 'secondary'
                          : 'destructive'
                      }
                    >
                      {profile.is_active && !profile.deleted_at && !profile.is_archived ? (
                        <><CheckCircle className="w-3 h-3 mr-1" /> Активен</>
                      ) : profile.subscription_status === 'frozen' ? (
                        <><ShieldOff className="w-3 h-3 mr-1" /> Заблокирован</>
                      ) : (
                        <><Ban className="w-3 h-3 mr-1" /> Неактивен</>
                      )}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge 
                      variant={
                        profile.subscription_status === 'active' 
                          ? 'default' 
                          : 'secondary'
                      }
                    >
                      {profile.subscription_status === 'active' ? 'Активна' : 'Неактивна'}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant={profile.monthly_activation_completed ? 'default' : 'secondary'}>
                      {profile.monthly_activation_completed ? 'Выполнена' : 'Не выполнена'}
                    </Badge>
                  </TableCell>
                  <TableCell>{((profile.realBalance ?? profile.balance ?? 0)).toLocaleString('ru-RU')} ₸</TableCell>
                  <TableCell>{new Date(profile.created_at).toLocaleDateString('ru-RU')}</TableCell>
                  <TableCell>
                    <div className="flex gap-1 justify-end flex-wrap">
                      {/* View network */}
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setNetworkDialog({
                          open: true,
                          userId: profile.id,
                          userName: profile.full_name || 'Пользователь',
                          userEmail: profile.email || ''
                        })}
                        title="Посмотреть структуру"
                      >
                        <Network className="h-4 w-4" />
                      </Button>

                      {/* Bind sponsor (only for users without sponsor) */}
                      {isSuperAdmin && !profile.sponsor_id && profile.is_active && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => setBindSponsorDialog({
                            open: true,
                            userId: profile.id,
                            userName: profile.full_name || 'Без имени'
                          })}
                          title="Привязать спонсора"
                        >
                          <UserPlus className="w-4 h-4" />
                        </Button>
                      )}

                      {/* Ban/Unban (real auth block) */}
                      {isSuperAdmin && profile.is_active && (
                        <Button
                          variant={profile.subscription_status === 'frozen' ? 'default' : 'outline'}
                          size="sm"
                          onClick={() => handleBanUser(profile.id, profile.subscription_status)}
                          disabled={banUser.isPending}
                          title={profile.subscription_status === 'frozen' ? 'Разблокировать вход' : 'Заблокировать вход'}
                        >
                          {profile.subscription_status === 'frozen' ? (
                            <CheckCircle className="w-4 h-4" />
                          ) : (
                            <Ban className="w-4 h-4" />
                          )}
                        </Button>
                      )}

                      {/* Archive (soft delete) */}
                      {isSuperAdmin && profile.is_active && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => openDeleteDialog(
                            profile.id, 
                            profile.full_name || 'Пользователь',
                            profile.email || '',
                            profile.sponsor_id,
                            'archive'
                          )}
                          title="Архивировать"
                        >
                          <Archive className="w-4 h-4" />
                        </Button>
                      )}

                      {/* Hard delete (permanent) */}
                      {isSuperAdmin && profile.is_active && (
                        <Button
                          variant="destructive"
                          size="sm"
                          onClick={() => openDeleteDialog(
                            profile.id, 
                            profile.full_name || 'Пользователь',
                            profile.email || '',
                            profile.sponsor_id,
                            'hard_delete'
                          )}
                          title="Удалить навсегда"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      )}

                      {/* Restore archived user */}
                      {isSuperAdmin && !profile.is_active && (
                        <Button
                          variant="default"
                          size="sm"
                          onClick={() => handleRestoreUser(profile.id)}
                          title="Восстановить"
                        >
                          <RotateCcw className="w-4 h-4" />
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialog.open} onOpenChange={(open) => setDeleteDialog({ ...deleteDialog, open })}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              {deleteDialog.mode === 'archive' ? (
                <><Archive className="h-5 w-5" /> Архивировать пользователя?</>
              ) : (
                <><Trash2 className="h-5 w-5 text-destructive" /> Удалить пользователя навсегда?</>
              )}
            </AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-4">
                <div>
                  <p className="font-medium">{deleteDialog.userName}</p>
                  <p className="text-sm text-muted-foreground">{deleteDialog.userEmail}</p>
                </div>

                {deleteDialog.referralsCount > 0 && (
                  <Alert variant="destructive">
                    <AlertTriangle className="h-4 w-4" />
                    <AlertDescription>
                      <p className="font-medium">У этого пользователя {deleteDialog.referralsCount} реферал(ов)!</p>
                      {deleteDialog.mode === 'hard_delete' ? (
                        <p className="text-sm mt-1">
                          Они потеряют спонсора (sponsor_id станет NULL) и не получат комиссий.
                        </p>
                      ) : (
                        <p className="text-sm mt-1">
                          Комиссии за них перестанут начисляться.
                        </p>
                      )}
                    </AlertDescription>
                  </Alert>
                )}

                {deleteDialog.referralsCount > 0 && deleteDialog.upperSponsorId && (
                  <div className="flex items-center space-x-2 p-3 bg-muted rounded-lg">
                    <Checkbox
                      id="reassign"
                      checked={deleteDialog.reassignReferrals}
                      onCheckedChange={(checked) => 
                        setDeleteDialog({ ...deleteDialog, reassignReferrals: checked as boolean })
                      }
                    />
                    <label htmlFor="reassign" className="text-sm cursor-pointer">
                      Пересадить рефералов на вышестоящего спонсора
                    </label>
                  </div>
                )}

                {deleteDialog.mode === 'hard_delete' && (
                  <p className="text-destructive font-medium">
                    ⚠️ Это действие необратимо! Все данные пользователя будут удалены.
                  </p>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleConfirmDelete}
              className={deleteDialog.mode === 'hard_delete' ? 'bg-destructive hover:bg-destructive/90' : ''}
            >
              {deleteDialog.mode === 'archive' ? 'Архивировать' : 'Удалить навсегда'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <BindSponsorDialog
        userId={bindSponsorDialog.userId}
        userName={bindSponsorDialog.userName}
        open={bindSponsorDialog.open}
        onOpenChange={(open) => setBindSponsorDialog({ ...bindSponsorDialog, open })}
        onSuccess={() => fetchProfiles()}
      />

      <UserNetworkDialog
        open={networkDialog.open}
        onOpenChange={(open) => setNetworkDialog({ ...networkDialog, open })}
        userId={networkDialog.userId}
        userName={networkDialog.userName}
        userEmail={networkDialog.userEmail}
      />
    </div>
  );
}
