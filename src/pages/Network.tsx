import { useState, useMemo, useCallback } from "react";
import { Users, UserPlus, Share2, Copy, Download, TrendingUp, AlertCircle, Clock, DollarSign, Eye } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { StructureSelector } from "@/components/Network/StructureSelector";
import { CommissionBreakdown } from "@/components/Network/CommissionBreakdown";
import { SimpleTabs, SimpleTabsList, SimpleTabsTrigger, SimpleTabsContent } from "@/components/Network/SimpleTabs";
import { useNetworkStats } from "@/hooks/useNetworkStats";
import { useNetworkTree, NetworkMember } from "@/hooks/useNetworkTree";
import { useNetworkActivity } from "@/hooks/useNetworkActivity";
import { useProfile } from "@/hooks/useProfile";
import { exportNetworkToCSV } from "@/utils/exportCSV";
import { toast } from "sonner";
import { getReferralLink, APP_CONFIG } from "@/config/constants";

const getActivityIcon = (type: string) => {
  switch (type) {
    case 'registration': return <UserPlus className="h-4 w-4" />;
    case 'activation': return <TrendingUp className="h-4 w-4" />;
    case 'freeze': return <AlertCircle className="h-4 w-4" />;
    case 'unfreeze': return <TrendingUp className="h-4 w-4" />;
    case 'purchase': return <DollarSign className="h-4 w-4" />;
    default: return <Clock className="h-4 w-4" />;
  }
};

const getActivityText = (type: string, payload: any) => {
  switch (type) {
    case 'registration': return 'Зарегистрировался по вашей ссылке';
    case 'activation': return `Выполнил активацию ${(payload?.amount || 0).toLocaleString('ru-RU')} ₸`;
    case 'freeze': return 'Аккаунт заморожен';
    case 'unfreeze': return 'Аккаунт разморожен';
    case 'purchase': return `Покупка на сумму ${(payload?.amount || 0).toLocaleString('ru-RU')} ₸`;
    default: return 'Действие';
  }
};

const getStatusBadge = (member: NetworkMember) => {
  if (member.subscription_status === 'active' || member.monthly_activation_met) {
    return <Badge className="profit-indicator">Активен</Badge>;
  }
  if (member.subscription_status === 'frozen') {
    return <Badge className="pending-indicator">Заморожен</Badge>;
  }
  return <Badge className="frozen-indicator">Ожидает активации</Badge>;
};

type NoCommissionReason =
  | 'not_activated'
  | 'no_payment_this_month'
  | 'too_deep'
  | 'level_not_unlocked'
  | 'marketing_free_access'
  | 'sponsor_inactive'
  | 'already_received_before'
  | 'no_active_subscription';

const NO_COMMISSION_TEXT: Record<NoCommissionReason, { title: string; description: string }> = {
  not_activated: {
    title: 'Партнёр не активен',
    description: 'Партнёр ещё не оплатил подписку или не прошёл активацию.',
  },
  no_payment_this_month: {
    title: 'Нет оплаты в этом месяце',
    description: 'Комиссия начисляется только за оплаты текущего месяца.',
  },
  no_active_subscription: {
    title: 'Нет активной подписки',
    description: 'Комиссия начисляется только за активных партнёров.',
  },
  too_deep: {
    title: 'Глубже 5 уровня',
    description: 'В структуре S1 комиссия начисляется только до 5-го уровня включительно.',
  },
  level_not_unlocked: {
    title: 'Уровень не открыт',
    description: 'Недостаточно активных личников на 1-й линии для открытия глубины.',
  },
  marketing_free_access: {
    title: 'Бесплатный доступ',
    description: 'За бесплатные (маркетинговые) подписки комиссия не начисляется.',
  },
  sponsor_inactive: {
    title: 'Вы были неактивны',
    description: 'В месяц оплаты партнёра у вас не была выполнена месячная активация.',
  },
  already_received_before: {
    title: 'Реанимация партнёра',
    description: 'Комиссия за этого партнёра уже начислялась ранее; повторно не начисляется.',
  },
};

function NoCommissionBadge({ reason }: { reason: string | null }) {
  if (!reason) return null;
  const info = (NO_COMMISSION_TEXT as any)[reason] as { title: string; description: string } | undefined;

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Badge className="cursor-pointer bg-warning text-warning-foreground hover:bg-warning/90">Нет начисления</Badge>
      </TooltipTrigger>
      <TooltipContent side="bottom" className="max-w-xs p-3">
        <div className="space-y-1">
          <p className="text-sm font-semibold">{info?.title ?? 'Нет начисления'}</p>
          <p className="text-xs text-muted-foreground">{info?.description ?? 'Причина не определена'}</p>
        </div>
      </TooltipContent>
    </Tooltip>
  );
}

export default function Network() {
  const [selectedMember, setSelectedMember] = useState<NetworkMember | null>(null);
  const [tab, setTab] = useState('tree');
  const [searchQuery, setSearchQuery] = useState('');
  const [filterLevel, setFilterLevel] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');
  const [filterCommission, setFilterCommission] = useState<'all' | 'with_commission' | 'without_commission'>('all');
  const [structureType, setStructureType] = useState<1 | 2>(1);
  
  // Dynamic max levels based on structure type
  const maxLevelsForStructure = structureType === 1 ? 5 : 10;
  
  const { data: stats, isLoading: statsLoading } = useNetworkStats(structureType);
  // Always load full data, filter only in UI
  const {
    data: networkMembers = [],
    isLoading: membersLoading,
    isFetching: membersFetching,
    error: membersError,
    refetch: refetchMembers,
  } = useNetworkTree(maxLevelsForStructure, structureType);
  const { data: activities = [], isLoading: activitiesLoading } = useNetworkActivity({ limit: 50 });
  const { data: profile } = useProfile();

  const filteredMembers = useMemo(() => {
    return networkMembers.filter(member => {
      const matchesSearch = !searchQuery || 
        member.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.email?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.referral_code?.toLowerCase().includes(searchQuery.toLowerCase());
      
      const matchesLevel = filterLevel === 'all' || member.level === parseInt(filterLevel);
      
      const matchesStatus = filterStatus === 'all' ||
        (filterStatus === 'active' && (member.subscription_status === 'active' || member.monthly_activation_met)) ||
        (filterStatus === 'inactive' && member.subscription_status === 'inactive' && !member.monthly_activation_met) ||
        (filterStatus === 'frozen' && member.subscription_status === 'frozen');

      const matchesCommission = structureType !== 1 || filterCommission === 'all' ||
        (filterCommission === 'with_commission' && member.has_commission_received === true) ||
        (filterCommission === 'without_commission' && member.has_commission_received === false && member.no_commission_reason !== null);
      
      return matchesSearch && matchesLevel && matchesStatus && matchesCommission;
    });
  }, [networkMembers, searchQuery, filterLevel, filterStatus, structureType, filterCommission]);

  // Calculate level stats
  const levelStats = useMemo(() => {
    const l1Count = networkMembers.filter(m => m.level === 1).length;
    const deepCount = networkMembers.filter(m => m.level > 1).length;
    return { l1Count, deepCount };
  }, [networkMembers]);

  const handleCopyLink = () => {
    const refCode = (profile as any)?.referral_code;
    if (refCode) {
      const referralLink = getReferralLink(refCode);
      navigator.clipboard.writeText(referralLink);
      toast.success("Реферальная ссылка скопирована!");
    }
  };

  const handleShareLink = async () => {
    const refCode = (profile as any)?.referral_code;
    if (!refCode) return;
    
    const referralLink = getReferralLink(refCode);
    
    if (navigator.share) {
      try {
        await navigator.share({
          title: "Присоединяйтесь к моей сети",
          text: "Используйте мою реферальную ссылку для регистрации",
          url: referralLink,
        });
        toast.success("Ссылка отправлена!");
      } catch {
        handleCopyLink();
      }
    } else {
      handleCopyLink();
    }
  };
  
  const handleExport = () => {
    if (filteredMembers.length === 0) {
      toast.error("Нет данных для экспорта");
      return;
    }
    exportNetworkToCSV(filteredMembers);
    toast.success("Данные экспортированы в CSV");
  };

  // Memoize level options to prevent re-renders
  const levelOptions = useMemo(() => 
    Array.from({ length: maxLevelsForStructure }, (_, i) => i + 1),
    [maxLevelsForStructure]
  );

  // Reset filters when structure type changes
  const handleStructureChange = useCallback((newType: 1 | 2) => {
    setStructureType(newType);
    setFilterLevel('all');
    setFilterStatus('all');
    setSearchQuery('');
    setFilterCommission('all');
  }, []);

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold">Моя сеть</h1>
          <p className="text-muted-foreground mt-1">Управление партнёрской структурой</p>
        </div>
        <div className="flex flex-col sm:flex-row gap-2">
          <Button variant="outline" className="gap-2 w-full sm:w-auto" onClick={handleExport}>
            <Download className="h-4 w-4" />
            <span className="sm:inline">Экспорт</span>
          </Button>
          <Button className="gap-2 w-full sm:w-auto" onClick={handleCopyLink}>
            <UserPlus className="h-4 w-4" />
            <span className="sm:inline">Пригласить партнёра</span>
          </Button>
        </div>
      </div>

      {/* Structure Selector */}
      <div className="mb-4">
        <StructureSelector value={structureType} onChange={handleStructureChange} />
      </div>

      {/* Stats row 1 */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
        <Card><CardContent className="p-6">
          {statsLoading ? <Skeleton className="h-20" /> : (
            <><p className="text-sm text-muted-foreground">Всего партнёров</p><p className="text-2xl font-bold">{stats?.total_partners || 0}</p></>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-6">
          {membersLoading ? <Skeleton className="h-20" /> : (
            <>
              <p className="text-sm text-muted-foreground">Прямые (L1)</p>
              <p className="text-2xl font-bold">{levelStats.l1Count}</p>
            </>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-6">
          {membersLoading ? <Skeleton className="h-20" /> : (
            <>
              <p className="text-sm text-muted-foreground">В глубине (L2-L{maxLevelsForStructure})</p>
              <p className="text-2xl font-bold">{levelStats.deepCount}</p>
            </>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-6">
          {statsLoading ? <Skeleton className="h-20" /> : (
            <>
              <p className="text-sm text-muted-foreground">Активных</p>
              <p className="text-2xl font-bold text-success">{stats?.active_partners || 0}</p>
            </>
          )}
        </CardContent></Card>
      </div>

      {/* Stats row 2 with commission breakdown */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
        <Card><CardContent className="p-6">
          {statsLoading ? <Skeleton className="h-20" /> : (
            <><p className="text-sm text-muted-foreground">Новые за месяц</p><p className="text-2xl font-bold">{stats?.new_this_month || 0}</p></>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-6">
          {statsLoading ? <Skeleton className="h-20" /> : (
            <><p className="text-sm text-muted-foreground">Активации</p><p className="text-2xl font-bold">{stats?.activations_this_month || 0}</p></>
          )}
        </CardContent></Card>
        <Card><CardContent className="p-6">
          {statsLoading ? <Skeleton className="h-20" /> : (
            <><p className="text-sm text-muted-foreground">Объём продаж</p><p className="text-2xl font-bold">{(stats?.volume_this_month || 0).toLocaleString('ru-RU')} ₸</p></>
          )}
        </CardContent></Card>
        {/* Commission breakdown card */}
        <CommissionBreakdown structureType={structureType} />
      </div>

      <Card>
        <CardHeader className="pb-4">
          <SimpleTabsList className="grid grid-cols-3">
            <SimpleTabsTrigger 
              value="tree" 
              isActive={tab === 'tree'} 
              onClick={() => setTab('tree')} 
              className="text-xs sm:text-sm px-2 py-2"
            >
              <span className="hidden sm:inline">Дерево структуры</span>
              <span className="sm:hidden">Дерево</span>
            </SimpleTabsTrigger>
            <SimpleTabsTrigger 
              value="list" 
              isActive={tab === 'list'} 
              onClick={() => setTab('list')} 
              className="text-xs sm:text-sm px-2 py-2"
            >
              <span className="hidden sm:inline">Список партнёров</span>
              <span className="sm:hidden">Список</span>
            </SimpleTabsTrigger>
            <SimpleTabsTrigger 
              value="activity" 
              isActive={tab === 'activity'} 
              onClick={() => setTab('activity')} 
              className="text-xs sm:text-sm px-2 py-2"
            >
              Активность
            </SimpleTabsTrigger>
          </SimpleTabsList>
        </CardHeader>
        <CardContent>
          <SimpleTabsContent value="tree" activeValue={tab} className="space-y-4 mt-0">
            {/* Quick filter buttons - only for S1 structure */}
            {structureType === 1 && (
              <div className="flex flex-wrap gap-2">
                <Button
                  variant={filterCommission === 'without_commission' ? 'default' : 'outline'}
                  size="sm"
                  className="gap-2"
                  onClick={() => setFilterCommission(filterCommission === 'without_commission' ? 'all' : 'without_commission')}
                >
                  <AlertCircle className="h-4 w-4" />
                  Только без начислений
                </Button>
                <Button
                  variant={filterCommission === 'with_commission' ? 'default' : 'outline'}
                  size="sm"
                  className="gap-2"
                  onClick={() => setFilterCommission(filterCommission === 'with_commission' ? 'all' : 'with_commission')}
                >
                  <DollarSign className="h-4 w-4" />
                  Только с начислениями
                </Button>
                {filterCommission !== 'all' && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setFilterCommission('all')}
                  >
                    Сбросить
                  </Button>
                )}
              </div>
            )}

            <div className="grid gap-4 md:grid-cols-4">
              <Input placeholder="Поиск..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
              <select
                value={filterLevel}
                onChange={(e) => setFilterLevel(e.target.value)}
                className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="all">Все уровни</option>
                {levelOptions.map(l => (
                  <option key={l} value={l.toString()}>{l} уровень</option>
                ))}
              </select>
              <select
                value={filterStatus}
                onChange={(e) => setFilterStatus(e.target.value)}
                className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option value="all">Все статусы</option>
                <option value="active">Активные</option>
                <option value="frozen">Замороженные</option>
                <option value="inactive">Неактивные</option>
              </select>
              {/* Commission filter select - only for S1 structure */}
              {structureType === 1 && (
                <select
                  value={filterCommission}
                  onChange={(e) => setFilterCommission(e.target.value as 'all' | 'with_commission' | 'without_commission')}
                  className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <option value="all">Все партнёры</option>
                  <option value="with_commission">С начислениями</option>
                  <option value="without_commission">Без начислений</option>
                </select>
              )}
            </div>
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>
                Показано: <span className="font-medium text-foreground">{filteredMembers.length}</span> из{' '}
                <span className="font-medium text-foreground">{networkMembers.length}</span>
                {membersFetching ? ' (обновление...)' : ''}
              </span>
              {(searchQuery || filterLevel !== 'all' || filterStatus !== 'all' || (structureType === 1 && filterCommission !== 'all')) && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setSearchQuery('');
                    setFilterLevel('all');
                    setFilterStatus('all');
                    setFilterCommission('all');
                  }}
                >
                  Сбросить фильтры
                </Button>
              )}
            </div>

            {membersError && (
              <div className="flex items-start justify-between gap-3 rounded-lg border border-destructive/30 bg-destructive/10 p-4">
                <div className="space-y-1">
                  <p className="font-medium">Не удалось загрузить партнёров</p>
                  <p className="text-sm text-muted-foreground">Попробуйте повторить загрузку.</p>
                </div>
                <Button variant="outline" onClick={() => refetchMembers()}>
                  Повторить
                </Button>
              </div>
            )}

            {membersLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-20" />
                <Skeleton className="h-20" />
                <Skeleton className="h-20" />
              </div>
            ) : filterLevel !== 'all' ? (
              /* При фильтре по конкретному уровню - показываем плоский список */
              filteredMembers.length === 0 ? (
                <div className="text-center py-12">
                  <Users className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
                  <p>Нет партнёров на уровне {filterLevel}</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {filteredMembers.map(m => (
                    <div key={m.partner_id} className="network-node active p-4 flex justify-between items-center">
                      <div className="flex items-center gap-3">
                        <div className={`w-2 h-2 rounded-full ${
                          m.subscription_status === 'active' || m.monthly_activation_met 
                            ? 'bg-success' 
                            : m.subscription_status === 'frozen' 
                            ? 'bg-warning' 
                            : 'bg-muted'
                        }`} />
                        <div className="space-y-1">
                          <div className="flex flex-wrap items-center gap-2">
                            <p className="font-medium">{m.full_name || 'Без имени'}</p>
                            {getStatusBadge(m)}
                            {m.has_commission_received === false && m.no_commission_reason && (
                              <NoCommissionBadge reason={m.no_commission_reason} />
                            )}
                          </div>
                          <p className="text-sm text-muted-foreground">{m.email}</p>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="font-medium">{m.monthly_volume.toLocaleString('ru-RU')} ₸</div>
                        <div className="text-xs text-muted-foreground">Команда: {m.total_team}</div>
                      </div>
                    </div>
                  ))}
                </div>
              )
            ) : (
              /* При "Все уровни" - показываем дерево с полными данными */
              <NetworkTree 
                members={filteredMembers} 
                filterCommission={structureType === 1 ? filterCommission : 'all'}
                isError={!!membersError}
                onRetry={() => refetchMembers()}
              />
            )}
          </SimpleTabsContent>

          <SimpleTabsContent value="list" activeValue={tab} className="mt-0">
            {membersLoading ? (
              <div className="space-y-2">
                {[...Array(5)].map((_, i) => (
                  <Skeleton key={i} className="h-16" />
                ))}
              </div>
            ) : filteredMembers.length === 0 ? (
              <div className="text-center py-12"><Users className="h-12 w-12 mx-auto mb-4 text-muted-foreground" /><p>Партнёры не найдены</p></div>
            ) : (
              <div className="space-y-2">{filteredMembers.map(m => (
                <div key={m.partner_id} className="network-node active p-4 flex justify-between">
                  <div><p className="font-medium">{m.full_name || 'Без имени'}</p><p className="text-sm text-muted-foreground">{m.email}</p></div>
                  <Button variant="ghost" size="sm" onClick={() => setSelectedMember(m)}><Eye className="h-4 w-4" /></Button>
                </div>
              ))}</div>
            )}
          </SimpleTabsContent>

          <SimpleTabsContent value="activity" activeValue={tab} className="mt-0">
            {activitiesLoading ? (
              <div className="space-y-4">
                {[...Array(5)].map((_, i) => (
                  <Skeleton key={i} className="h-16" />
                ))}
              </div>
            ) : activities.length === 0 ? (
              <div className="text-center py-12"><Clock className="h-12 w-12 mx-auto mb-4 text-muted-foreground" /><p>Нет активности</p></div>
            ) : (
              <div className="space-y-4">{activities.map(a => (
                <div key={a.id} className="flex items-start gap-4 p-4 border rounded">
                  {getActivityIcon(a.type)}
                  <div className="flex-1"><p className="font-medium">{a.user_name || a.user_email}</p><p className="text-sm text-muted-foreground">{getActivityText(a.type, a.payload)}</p></div>
                </div>
              ))}</div>
            )}
          </SimpleTabsContent>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4 sm:p-6">
          <div className="flex flex-col sm:flex-row sm:justify-between gap-4">
            <code className="text-xs sm:text-sm break-all">
              {(profile as any)?.referral_code 
                ? getReferralLink((profile as any).referral_code)
                : `${APP_CONFIG.DOMAIN}/register`}
            </code>
            <div className="flex flex-col sm:flex-row gap-2">
              <Button size="sm" className="w-full sm:w-auto" onClick={handleCopyLink}>
                <Copy className="h-4 w-4 mr-2" />
                Копировать
              </Button>
              <Button size="sm" className="w-full sm:w-auto" onClick={handleShareLink}>
                <Share2 className="h-4 w-4 mr-2" />
                Поделиться
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
      
      <Dialog open={!!selectedMember} onOpenChange={() => setSelectedMember(null)}>
        <DialogContent><DialogHeader><DialogTitle>Карточка партнёра</DialogTitle></DialogHeader>{selectedMember && (<div className="space-y-4"><h3 className="font-semibold">{selectedMember.full_name}</h3><p className="text-sm">{selectedMember.email}</p></div>)}</DialogContent>
      </Dialog>
    </div>
  );
}
