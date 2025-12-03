import { useState, useMemo } from "react";
import { Users, UserPlus, Share2, Copy, Download, TrendingUp, AlertCircle, Clock, DollarSign, Eye } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { StructureSelector } from "@/components/Network/StructureSelector";
import { CommissionBreakdown } from "@/components/Network/CommissionBreakdown";
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
    case 'activation': return `Выполнил активацию $${payload?.amount || 0}`;
    case 'freeze': return 'Аккаунт заморожен';
    case 'unfreeze': return 'Аккаунт разморожен';
    case 'purchase': return `Покупка на сумму $${payload?.amount || 0}`;
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

export default function Network() {
  const [selectedMember, setSelectedMember] = useState<NetworkMember | null>(null);
  const [tab, setTab] = useState('tree');
  const [searchQuery, setSearchQuery] = useState('');
  const [filterLevel, setFilterLevel] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');
  const [structureType, setStructureType] = useState<1 | 2>(1);
  
  // Dynamic max levels based on structure type
  const maxLevelsForStructure = structureType === 1 ? 5 : 10;
  const maxLevel = filterLevel === 'all' ? maxLevelsForStructure : parseInt(filterLevel);
  
  const { data: stats, isLoading: statsLoading } = useNetworkStats(structureType);
  const { data: networkMembers = [], isLoading: membersLoading } = useNetworkTree(maxLevel, structureType);
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
      
      return matchesSearch && matchesLevel && matchesStatus;
    });
  }, [networkMembers, searchQuery, filterLevel, filterStatus]);

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

  // Reset filter level when structure type changes
  const handleStructureChange = (newType: 1 | 2) => {
    setStructureType(newType);
    setFilterLevel('all');
  };

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
            <><p className="text-sm text-muted-foreground">Объём продаж</p><p className="text-2xl font-bold">${stats?.volume_this_month?.toFixed(0) || 0}</p></>
          )}
        </CardContent></Card>
        {/* Commission breakdown card */}
        <CommissionBreakdown structureType={structureType} />
      </div>

      <Card>
        <CardHeader>
          <Tabs value={tab} onValueChange={setTab}>
            <TabsList className="grid w-full grid-cols-3 h-auto">
              <TabsTrigger value="tree" className="text-xs sm:text-sm px-2 py-2">
                <span className="hidden sm:inline">Дерево структуры</span>
                <span className="sm:hidden">Дерево</span>
              </TabsTrigger>
              <TabsTrigger value="list" className="text-xs sm:text-sm px-2 py-2">
                <span className="hidden sm:inline">Список партнёров</span>
                <span className="sm:hidden">Список</span>
              </TabsTrigger>
              <TabsTrigger value="activity" className="text-xs sm:text-sm px-2 py-2">
                Активность
              </TabsTrigger>
            </TabsList>

            <TabsContent value="tree" className="space-y-4">
              <div className="grid gap-4 md:grid-cols-3">
                <Input placeholder="Поиск..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
                <Select value={filterLevel} onValueChange={setFilterLevel}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все уровни</SelectItem>
                    {Array.from({ length: maxLevelsForStructure }, (_, i) => i + 1).map(l => (
                      <SelectItem key={l} value={l.toString()}>{l} уровень</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select value={filterStatus} onValueChange={setFilterStatus}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все</SelectItem>
                    <SelectItem value="active">Активные</SelectItem>
                    <SelectItem value="frozen">Замороженные</SelectItem>
                    <SelectItem value="inactive">Неактивные</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {membersLoading ? (
                <div className="space-y-2">
                  <Skeleton className="h-20" />
                  <Skeleton className="h-20" />
                  <Skeleton className="h-20" />
                </div>
              ) : (
                <NetworkTree members={filteredMembers} />
              )}
            </TabsContent>

            <TabsContent value="list">
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
            </TabsContent>

            <TabsContent value="activity">
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
            </TabsContent>
          </Tabs>
        </CardHeader>
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
