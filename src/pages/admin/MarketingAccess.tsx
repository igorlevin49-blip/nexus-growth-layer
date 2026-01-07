import { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useLoader } from "@/contexts/LoaderContext";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "sonner";
import { Search, Gift, AlertTriangle, Settings, Download } from "lucide-react";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { formatKZT } from "@/utils/formatMoney";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

interface UserWithSubscription {
  id: string;
  full_name: string;
  email: string;
  subscription: {
    id: string;
    status: string;
    is_marketing_free_access: boolean;
    expires_at: string | null;
    amount_usd: number;
    created_at: string;
  } | null;
  s1_commissions_total: number;
  s1_commissions_count: number;
  has_reversals: boolean;
}

interface SubscriptionWithProfile {
  id: string;
  user_id: string;
  status: string;
  is_marketing_free_access: boolean | null;
  expires_at: string | null;
  amount_usd: number;
  created_at: string;
  profiles: {
    id: string;
    full_name: string | null;
    email: string | null;
  } | null;
}

export default function MarketingAccess() {
  const { user, userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const queryClient = useQueryClient();
  const { disableAutoLoader, enableAutoLoader } = useLoader();
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedUser, setSelectedUser] = useState<UserWithSubscription | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [showReverseDialog, setShowReverseDialog] = useState(false);
  const [reverseComment, setReverseComment] = useState("");

  // Disable global preloader on this page
  useEffect(() => {
    disableAutoLoader();
    return () => enableAutoLoader();
  }, [disableAutoLoader, enableAutoLoader]);

  // Load all active subscriptions with profiles
  const { data: allSubscriptions, isLoading: isLoadingAll } = useQuery({
    queryKey: ['marketing-access-all'],
    queryFn: async () => {
      // Get subscriptions
      const { data: subscriptions, error: subError } = await supabase
        .from('subscriptions')
        .select('id, user_id, status, is_marketing_free_access, expires_at, amount_usd, created_at')
        .eq('status', 'active')
        .order('created_at', { ascending: false });

      if (subError) throw subError;
      if (!subscriptions || subscriptions.length === 0) return [];

      // Get profiles for these users
      const userIds = [...new Set(subscriptions.map(s => s.user_id))];
      const { data: profiles, error: profError } = await supabase
        .from('profiles')
        .select('id, full_name, email')
        .in('id', userIds);

      if (profError) throw profError;

      // Combine data
      return subscriptions.map(sub => ({
        ...sub,
        profiles: profiles?.find(p => p.id === sub.user_id) || null,
      })) as SubscriptionWithProfile[];
    },
  });

  // Filter subscriptions by search query
  const filteredSubscriptions = allSubscriptions?.filter((sub) => {
    if (!searchQuery || searchQuery.length < 2) return true;
    const query = searchQuery.toLowerCase();
    const fullName = sub.profiles?.full_name?.toLowerCase() || '';
    const email = sub.profiles?.email?.toLowerCase() || '';
    return fullName.includes(query) || email.includes(query);
  });

  // Load detailed user info
  const { data: userDetails, isLoading: isLoadingDetails } = useQuery({
    queryKey: ['marketing-access-details', selectedUser?.id],
    queryFn: async () => {
      if (!selectedUser) return null;

      // Get S1 commissions total
      const { data: commissions, error: commError } = await supabase
        .from('transactions')
        .select('amount_cents, id')
        .eq('type', 'commission')
        .eq('structure_type', 'primary')
        .eq('status', 'completed')
        .contains('payload', { payer_id: selectedUser.id, type: 'S1' });

      if (commError) throw commError;

      // Check for existing reversals
      const { data: reversals, error: revError } = await supabase
        .from('transactions')
        .select('id')
        .eq('type', 'adjustment')
        .contains('payload', { reversal_source_user_id: selectedUser.id, reversal_type: 'marketing_free_access' })
        .limit(1);

      if (revError) throw revError;

      const totalCents = commissions?.reduce((sum, c) => sum + c.amount_cents, 0) || 0;

      return {
        ...selectedUser,
        s1_commissions_total: totalCents,
        s1_commissions_count: commissions?.length || 0,
        has_reversals: (reversals?.length || 0) > 0,
      };
    },
    enabled: !!selectedUser,
  });

  // Toggle marketing free access flag
  const toggleMarketingAccessMutation = useMutation({
    mutationFn: async ({ subscriptionId, value }: { subscriptionId: string; value: boolean }) => {
      const { error } = await supabase
        .from('subscriptions')
        .update({ is_marketing_free_access: value })
        .eq('id', subscriptionId);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['marketing-access-all'] });
      queryClient.invalidateQueries({ queryKey: ['marketing-access-details'] });
      toast.success("Статус маркетингового доступа обновлён");
    },
    onError: (error) => {
      toast.error(`Ошибка: ${error.message}`);
    },
  });

  // Reverse commissions
  const reverseCommissionsMutation = useMutation({
    mutationFn: async ({ userId, comment }: { userId: string; comment: string }) => {
      if (!user) throw new Error("Не авторизован");

      const { data, error } = await supabase.rpc('reverse_marketing_free_commissions', {
        p_source_user_id: userId,
        p_admin_id: user.id,
        p_comment: comment,
      });

      if (error) throw error;
      
      const result = data as any;
      if (!result.success) throw new Error(result.message || result.error);

      return result as {
        success: boolean;
        total_reversed_cents: number;
        reversal_count: number;
        affected_users_count: number;
      };
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['marketing-access-details'] });
      toast.success(`Обнулено ${data.reversal_count} начислений на сумму ${formatKZT(data.total_reversed_cents)}`);
      setShowReverseDialog(false);
      setReverseComment("");
    },
    onError: (error) => {
      toast.error(`Ошибка: ${error.message}`);
    },
  });

  const handleSelectUser = (sub: SubscriptionWithProfile) => {
    setSelectedUser({
      id: sub.user_id,
      full_name: sub.profiles?.full_name || 'Без имени',
      email: sub.profiles?.email || '',
      subscription: {
        id: sub.id,
        status: sub.status,
        is_marketing_free_access: sub.is_marketing_free_access || false,
        expires_at: sub.expires_at,
        amount_usd: sub.amount_usd,
        created_at: sub.created_at,
      },
      s1_commissions_total: 0,
      s1_commissions_count: 0,
      has_reversals: false,
    });
    setDialogOpen(true);
  };

  const handleReverse = () => {
    if (!selectedUser || !reverseComment.trim()) {
      toast.error("Укажите комментарий для обнуления");
      return;
    }
    reverseCommissionsMutation.mutate({
      userId: selectedUser.id,
      comment: reverseComment,
    });
  };

  const handleExportCSV = async () => {
    try {
      // Get all subscriptions with marketing free access
      const { data: subscriptions, error: subError } = await supabase
        .from('subscriptions')
        .select('id, user_id, status, is_marketing_free_access, expires_at, amount_usd, started_at, created_at')
        .eq('is_marketing_free_access', true)
        .order('created_at', { ascending: false });

      if (subError) throw subError;
      if (!subscriptions || subscriptions.length === 0) {
        toast.info("Нет пользователей с маркетинговым доступом");
        return;
      }

      // Get profiles for these users
      const userIds = [...new Set(subscriptions.map(s => s.user_id))];
      const { data: profiles, error: profError } = await supabase
        .from('profiles')
        .select('id, full_name, email, phone, telegram_username, referral_code, created_at, sponsor_id')
        .in('id', userIds);

      if (profError) throw profError;

      // Get sponsor info
      const sponsorIds = [...new Set(profiles?.map(p => p.sponsor_id).filter(Boolean) || [])];
      let sponsors: { id: string; full_name: string | null; email: string | null }[] = [];
      if (sponsorIds.length > 0) {
        const { data: sponsorData } = await supabase
          .from('profiles')
          .select('id, full_name, email')
          .in('id', sponsorIds);
        sponsors = sponsorData || [];
      }

      // Build CSV data
      const csvData = subscriptions.map(sub => {
        const profile = profiles?.find(p => p.id === sub.user_id);
        const sponsor = sponsors.find(s => s.id === profile?.sponsor_id);
        return {
          'ФИО': profile?.full_name || 'Без имени',
          'Email': profile?.email || '',
          'Телефон': profile?.phone || '',
          'Telegram': profile?.telegram_username || '',
          'Реферальный код': profile?.referral_code || '',
          'Дата регистрации': profile?.created_at ? format(new Date(profile.created_at), 'dd.MM.yyyy', { locale: ru }) : '',
          'Дата начала подписки': sub.started_at ? format(new Date(sub.started_at), 'dd.MM.yyyy', { locale: ru }) : '',
          'Дата окончания подписки': sub.expires_at ? format(new Date(sub.expires_at), 'dd.MM.yyyy', { locale: ru }) : '',
          'Сумма USD': sub.amount_usd,
          'Статус подписки': sub.status,
          'Спонсор ФИО': sponsor?.full_name || '',
          'Спонсор Email': sponsor?.email || '',
        };
      });

      // Generate CSV
      const headers = Object.keys(csvData[0]);
      const rows = csvData.map(row => headers.map(h => row[h as keyof typeof row]));
      const csvContent = [
        headers.join(';'),
        ...rows.map(row => row.map(cell => `"${cell ?? ''}"`).join(';'))
      ].join('\n');

      // Download
      const blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8;' });
      const link = document.createElement('a');
      const url = URL.createObjectURL(blob);
      const dateStr = format(new Date(), 'yyyy-MM-dd');
      
      link.setAttribute('href', url);
      link.setAttribute('download', `marketing-free-users-${dateStr}.csv`);
      link.style.visibility = 'hidden';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);

      toast.success(`Экспортировано ${csvData.length} записей`);
    } catch (error: any) {
      toast.error(`Ошибка экспорта: ${error.message}`);
    }
  };

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center gap-2">
        <Gift className="h-8 w-8 text-primary" />
        <div>
          <h1 className="text-3xl font-bold">Маркетинговый доступ</h1>
          <p className="text-muted-foreground">
            Управление бесплатными подписками без начисления комиссий S1
          </p>
        </div>
      </div>

      {/* Users Table */}
      <Card>
        <CardHeader className="flex flex-row items-start justify-between">
          <div>
            <CardTitle>Пользователи с активными подписками</CardTitle>
            <CardDescription>
              Всего: {allSubscriptions?.length || 0} активных подписок
            </CardDescription>
          </div>
          <Button variant="outline" onClick={handleExportCSV}>
            <Download className="h-4 w-4 mr-2" />
            Экспорт бесплатников
          </Button>
        </CardHeader>
        <CardContent>
          {/* Search */}
          <div className="relative mb-4">
            <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Поиск по имени или email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>

          {isLoadingAll ? (
            <p className="text-sm text-muted-foreground">Загрузка...</p>
          ) : (
            <div className="rounded-md border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Пользователь</TableHead>
                    <TableHead>Сумма</TableHead>
                    <TableHead>Статус</TableHead>
                    <TableHead>Маркетинг</TableHead>
                    <TableHead>Дата</TableHead>
                    <TableHead className="text-right">Действия</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredSubscriptions?.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} className="text-center text-muted-foreground py-8">
                        {searchQuery.length >= 2 ? 'Пользователи не найдены' : 'Нет активных подписок'}
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredSubscriptions?.map((sub) => (
                      <TableRow 
                        key={sub.id} 
                        className={selectedUser?.subscription?.id === sub.id ? 'bg-accent' : ''}
                      >
                        <TableCell>
                          <div className="font-medium">{sub.profiles?.full_name || 'Без имени'}</div>
                          <div className="text-xs text-muted-foreground">{sub.profiles?.email}</div>
                        </TableCell>
                        <TableCell>
                          <span className="font-medium">${sub.amount_usd}</span>
                        </TableCell>
                        <TableCell>
                          <Badge variant="default">Активна</Badge>
                        </TableCell>
                        <TableCell>
                          {sub.is_marketing_free_access ? (
                            <Badge variant="secondary">Бесплатный</Badge>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TableCell>
                        <TableCell>
                          <span className="text-sm text-muted-foreground">
                            {format(new Date(sub.created_at), 'dd.MM.yyyy', { locale: ru })}
                          </span>
                        </TableCell>
                        <TableCell className="text-right">
                          {isSuperAdmin ? (
                            <Button 
                              size="sm" 
                              variant="default"
                              onClick={() => handleSelectUser(sub)}
                            >
                              <Settings className="h-4 w-4 mr-1" />
                              Управлять
                            </Button>
                          ) : (
                            sub.is_marketing_free_access ? (
                              <Badge variant="secondary">Бесплатный</Badge>
                            ) : (
                              <span className="text-muted-foreground">—</span>
                            )
                          )}
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* User Details Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {selectedUser?.full_name}
              {userDetails?.has_reversals && (
                <Badge variant="outline">Обнулено</Badge>
              )}
            </DialogTitle>
            <DialogDescription>{selectedUser?.email}</DialogDescription>
          </DialogHeader>
          
          {selectedUser?.subscription && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <Label className="text-base">Подписка</Label>
                  <p className="text-sm text-muted-foreground">
                    {selectedUser.subscription.status === 'active' ? 'Активна' : 'Неактивна'}
                    {selectedUser.subscription.expires_at && 
                      ` до ${new Date(selectedUser.subscription.expires_at).toLocaleDateString('ru-RU')}`
                    }
                  </p>
                </div>
                <Badge variant={selectedUser.subscription.status === 'active' ? 'default' : 'secondary'}>
                  ${selectedUser.subscription.amount_usd}
                </Badge>
              </div>

              {/* Marketing Free Access Toggle */}
              <div className="flex items-center justify-between p-4 border rounded-lg bg-accent/50">
                <div className="space-y-1">
                  <Label htmlFor="marketing-access" className="text-base">
                    Бесплатный маркетинговый доступ
                  </Label>
                  <p className="text-sm text-muted-foreground">
                    Не начислять комиссии S1 по этой подписке
                  </p>
                </div>
                <Switch
                  id="marketing-access"
                  checked={selectedUser.subscription.is_marketing_free_access}
                  onCheckedChange={(checked) =>
                    toggleMarketingAccessMutation.mutate({
                      subscriptionId: selectedUser.subscription!.id,
                      value: checked,
                    })
                  }
                  disabled={toggleMarketingAccessMutation.isPending}
                />
              </div>

              {/* S1 Commissions Info */}
              <div className="space-y-2">
                <Label className="text-base">Начисления S1 от этого пользователя</Label>
                {isLoadingDetails ? (
                  <p className="text-sm text-muted-foreground">Загрузка данных о комиссиях...</p>
                ) : (
                  <div className="flex gap-4 text-sm">
                    <div>
                      <span className="text-muted-foreground">Сумма:</span>{" "}
                      <span className="font-medium">{formatKZT(userDetails?.s1_commissions_total || 0)}</span>
                    </div>
                    <div>
                      <span className="text-muted-foreground">Транзакций:</span>{" "}
                      <span className="font-medium">{userDetails?.s1_commissions_count || 0}</span>
                    </div>
                  </div>
                )}
              </div>

              {/* Reverse Button */}
              {!isLoadingDetails && !userDetails?.has_reversals && (userDetails?.s1_commissions_count || 0) > 0 && (
                <div className="space-y-4 p-4 border border-destructive/50 rounded-lg">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="h-5 w-5 text-destructive mt-0.5" />
                    <div className="space-y-2 flex-1">
                      <Label className="text-base text-destructive">Обнуление начислений S1</Label>
                      <p className="text-sm text-muted-foreground">
                        Все начисления по структуре 1 от этого пользователя будут обнулены через корректирующие записи.
                        Это действие нельзя отменить.
                      </p>
                      <Button
                        variant="destructive"
                        onClick={() => setShowReverseDialog(true)}
                        disabled={reverseCommissionsMutation.isPending}
                      >
                        Обнулить начисления S1
                      </Button>
                    </div>
                  </div>
                </div>
              )}

              {userDetails?.has_reversals && (
                <div className="p-4 border border-green-500/50 rounded-lg bg-green-500/10">
                  <p className="text-sm text-green-700 dark:text-green-300">
                    ✓ Начисления по этому пользователю уже были обнулены
                  </p>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Reverse Confirmation Dialog */}
      <AlertDialog open={showReverseDialog} onOpenChange={setShowReverseDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Подтвердите обнуление</AlertDialogTitle>
            <AlertDialogDescription>
              Вы собираетесь обнулить {userDetails?.s1_commissions_count} начислений на общую сумму{" "}
              {formatKZT(userDetails?.s1_commissions_total || 0)}.
              <br /><br />
              Будут созданы корректирующие записи для всех затронутых партнёров.
              Это действие нельзя отменить.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="space-y-2">
            <Label htmlFor="comment">Комментарий (обязательно)</Label>
            <Textarea
              id="comment"
              value={reverseComment}
              onChange={(e) => setReverseComment(e.target.value)}
              placeholder="Укажите причину обнуления (например: Маркетинговая акция Q4 2024)"
              rows={3}
            />
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleReverse}
              disabled={!reverseComment.trim() || reverseCommissionsMutation.isPending}
              className="bg-destructive hover:bg-destructive/90"
            >
              {reverseCommissionsMutation.isPending ? "Обработка..." : "Обнулить"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
