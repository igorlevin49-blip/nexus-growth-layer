import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { Ban, CheckCircle, XCircle, Trash2, RotateCcw, UserPlus, Network, Search } from "lucide-react";
import { useSoftDeleteUser, useRestoreUser } from "@/hooks/useCleanupTestData";
import { BindSponsorDialog } from "@/components/Admin/BindSponsorDialog";
import { UserNetworkDialog } from "@/components/Admin/UserNetworkDialog";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";

interface Profile {
  id: string;
  full_name: string | null;
  email: string | null;
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
}

export default function AdminUsers() {
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
  const softDeleteUser = useSoftDeleteUser();
  const restoreUser = useRestoreUser();

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

      // По умолчанию не показываем архивных
      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      // Поиск по email, имени, ID, referral_code
      if (searchQuery.trim()) {
        const search = searchQuery.trim();
        
        // Проверка, является ли строка валидным UUID
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        // Строим фильтр OR с условием для UUID только если строка валидна
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
      setProfiles(data || []);
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

  const toggleUserStatus = async (userId: string, currentStatus: string) => {
    const newStatus = currentStatus === 'active' ? 'frozen' : 'active';
    
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ subscription_status: newStatus })
        .eq('id', userId);

      if (error) throw error;

      toast({
        title: "Успешно",
        description: `Статус пользователя изменен на ${newStatus}`,
      });

      fetchProfiles();
    } catch (error) {
      console.error('Error updating user status:', error);
      toast({
        title: "Ошибка",
        description: "Не удалось обновить статус пользователя",
        variant: "destructive",
      });
    }
  };

  const handleDeleteUser = async (userId: string) => {
    await softDeleteUser.mutateAsync(userId);
    fetchProfiles();
  };

  const handleRestoreUser = async (userId: string) => {
    await restoreUser.mutateAsync(userId);
    fetchProfiles();
  };

  if (loading) {
    return <div className="flex items-center justify-center h-96">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Управление пользователями</CardTitle>
          <div className="flex items-center gap-2">
            <Button
              onClick={runDiagnose}
              variant="outline"
              size="sm"
            >
              Диагностика
            </Button>
            <Button
              onClick={runBackfill}
              variant="outline"
              size="sm"
            >
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
                <TableHead>Пригласивший</TableHead>
                <TableHead>Статус аккаунта</TableHead>
                <TableHead>Статус подписки</TableHead>
                <TableHead>Активация</TableHead>
                <TableHead>Баланс (USD)</TableHead>
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
                    {(() => {
                      // Check if sponsor exists and is active
                      const sponsorIsDeleted = profile.sponsor?.deleted_at || profile.sponsor?.is_archived || !profile.sponsor?.is_active;
                      
                      if (profile.sponsor && !sponsorIsDeleted) {
                        // Show live sponsor data
                        return (
                          <div className="text-sm">
                            <div className="font-medium">{profile.sponsor.full_name || 'Не указано'}</div>
                            <div className="text-muted-foreground">{profile.sponsor.email}</div>
                          </div>
                        );
                      } else if (profile.referrer_snapshot) {
                        // Show snapshot if sponsor is deleted/archived
                        return (
                          <div className="text-sm">
                            <div className="font-medium">{profile.referrer_snapshot.full_name || 'Не указано'}</div>
                            <div className="text-muted-foreground">{profile.referrer_snapshot.email}</div>
                            <Badge variant="secondary" className="mt-1">архив</Badge>
                          </div>
                        );
                      } else if (profile.sponsor_id) {
                        // Has sponsor_id but no data (shouldn't happen normally)
                        return (
                          <div className="text-sm">
                            <div className="text-muted-foreground">Данные недоступны</div>
                            <Badge variant="secondary" className="mt-1">архив</Badge>
                          </div>
                        );
                      } else {
                        // No sponsor at all
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
                        <><XCircle className="w-3 h-3 mr-1" /> Заморожен</>
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
                  <TableCell>${profile.balance?.toFixed(2) || '0.00'}</TableCell>
                  <TableCell>{new Date(profile.created_at).toLocaleDateString('ru-RU')}</TableCell>
                  <TableCell>
                    <div className="flex gap-2 justify-end">
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
                      {!profile.sponsor_id && profile.is_active && (
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
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => toggleUserStatus(profile.id, profile.subscription_status)}
                        disabled={!profile.is_active}
                        title={profile.subscription_status === 'active' ? 'Заблокировать' : 'Разблокировать'}
                      >
                        <Ban className="w-4 h-4" />
                      </Button>
                      {profile.is_active ? (
                        <Button
                          variant="destructive"
                          size="sm"
                          onClick={() => handleDeleteUser(profile.id)}
                          title="Удалить"
                        >
                          <Trash2 className="w-4 h-4" />
                        </Button>
                      ) : (
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
