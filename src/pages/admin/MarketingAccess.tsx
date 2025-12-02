import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "sonner";
import { Search, Gift, AlertTriangle } from "lucide-react";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { formatCents } from "@/utils/formatMoney";

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
  } | null;
  s1_commissions_total: number;
  s1_commissions_count: number;
  has_reversals: boolean;
}

export default function MarketingAccess() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedUser, setSelectedUser] = useState<UserWithSubscription | null>(null);
  const [showReverseDialog, setShowReverseDialog] = useState(false);
  const [reverseComment, setReverseComment] = useState("");

  // Search users
  const { data: searchResults, isLoading: isSearching } = useQuery({
    queryKey: ['marketing-access-search', searchQuery],
    queryFn: async () => {
      if (!searchQuery || searchQuery.length < 2) return [];

      const { data, error } = await supabase
        .from('profiles')
        .select(`
          id,
          full_name,
          email,
          subscriptions!inner(
            id,
            status,
            is_marketing_free_access,
            expires_at,
            amount_usd
          )
        `)
        .or(`full_name.ilike.%${searchQuery}%,email.ilike.%${searchQuery}%`)
        .eq('subscriptions.status', 'active')
        .limit(10);

      if (error) throw error;
      return data || [];
    },
    enabled: searchQuery.length >= 2,
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
        s1_commissions_total: totalCents / 100,
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
      queryClient.invalidateQueries({ queryKey: ['marketing-access-search'] });
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
      toast.success(`Обнулено ${data.reversal_count} начислений на сумму ${formatCents(data.total_reversed_cents)}`);
      setShowReverseDialog(false);
      setReverseComment("");
    },
    onError: (error) => {
      toast.error(`Ошибка: ${error.message}`);
    },
  });

  const handleSelectUser = (user: any) => {
    const subscription = user.subscriptions?.[0];
    setSelectedUser({
      id: user.id,
      full_name: user.full_name,
      email: user.email,
      subscription: subscription ? {
        id: subscription.id,
        status: subscription.status,
        is_marketing_free_access: subscription.is_marketing_free_access,
        expires_at: subscription.expires_at,
        amount_usd: subscription.amount_usd,
      } : null,
      s1_commissions_total: 0,
      s1_commissions_count: 0,
      has_reversals: false,
    });
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

      {/* Search */}
      <Card>
        <CardHeader>
          <CardTitle>Поиск пользователя</CardTitle>
          <CardDescription>Найдите пользователя по имени или email</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Введите имя или email..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>

          {isSearching && <p className="text-sm text-muted-foreground mt-2">Поиск...</p>}

          {searchResults && searchResults.length > 0 && (
            <div className="mt-4 space-y-2">
              {searchResults.map((user: any) => (
                <div
                  key={user.id}
                  onClick={() => handleSelectUser(user)}
                  className="p-3 border rounded-lg cursor-pointer hover:bg-accent transition-colors"
                >
                  <div className="font-medium">{user.full_name}</div>
                  <div className="text-sm text-muted-foreground">{user.email}</div>
                </div>
              ))}
            </div>
          )}

          {searchQuery.length >= 2 && !isSearching && searchResults?.length === 0 && (
            <p className="text-sm text-muted-foreground mt-2">Пользователи не найдены</p>
          )}
        </CardContent>
      </Card>

      {/* User Details */}
      {userDetails && (
        <Card>
          <CardHeader>
            <CardTitle>
              {userDetails.full_name}
              {userDetails.has_reversals && (
                <Badge variant="outline" className="ml-2">
                  Обнулено
                </Badge>
              )}
            </CardTitle>
            <CardDescription>{userDetails.email}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Subscription Info */}
            {userDetails.subscription && (
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <Label className="text-base">Подписка</Label>
                    <p className="text-sm text-muted-foreground">
                      {userDetails.subscription.status === 'active' ? 'Активна' : 'Неактивна'}
                      {userDetails.subscription.expires_at && 
                        ` до ${new Date(userDetails.subscription.expires_at).toLocaleDateString('ru-RU')}`
                      }
                    </p>
                  </div>
                  <Badge variant={userDetails.subscription.status === 'active' ? 'default' : 'secondary'}>
                    {formatCents(userDetails.subscription.amount_usd * 100)}
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
                    checked={userDetails.subscription.is_marketing_free_access}
                    onCheckedChange={(checked) =>
                      toggleMarketingAccessMutation.mutate({
                        subscriptionId: userDetails.subscription!.id,
                        value: checked,
                      })
                    }
                    disabled={toggleMarketingAccessMutation.isPending}
                  />
                </div>

                {/* S1 Commissions Info */}
                <div className="space-y-2">
                  <Label className="text-base">Начисления S1 от этого пользователя</Label>
                  <div className="flex gap-4 text-sm">
                    <div>
                      <span className="text-muted-foreground">Сумма:</span>{" "}
                      <span className="font-medium">{formatCents(userDetails.s1_commissions_total * 100)}</span>
                    </div>
                    <div>
                      <span className="text-muted-foreground">Транзакций:</span>{" "}
                      <span className="font-medium">{userDetails.s1_commissions_count}</span>
                    </div>
                  </div>
                </div>

                {/* Reverse Button */}
                {!userDetails.has_reversals && userDetails.s1_commissions_count > 0 && (
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

                {userDetails.has_reversals && (
                  <div className="p-4 border border-green-500/50 rounded-lg bg-green-500/10">
                    <p className="text-sm text-green-700 dark:text-green-300">
                      ✓ Начисления по этому пользователю уже были обнулены
                    </p>
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Reverse Confirmation Dialog */}
      <AlertDialog open={showReverseDialog} onOpenChange={setShowReverseDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Подтвердите обнуление</AlertDialogTitle>
            <AlertDialogDescription>
              Вы собираетесь обнулить {userDetails?.s1_commissions_count} начислений на общую сумму{" "}
              {formatCents((userDetails?.s1_commissions_total || 0) * 100)}.
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
