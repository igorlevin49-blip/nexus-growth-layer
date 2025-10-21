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
import { useNetworkStats } from "@/hooks/useNetworkStats";
import { useNetworkTree, NetworkMember } from "@/hooks/useNetworkTree";
import { useNetworkActivity } from "@/hooks/useNetworkActivity";
import { exportNetworkToCSV } from "@/utils/exportCSV";
import { toast } from "sonner";

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
  return <Badge className="frozen-indicator">Неактивен</Badge>;
};

export default function Network() {
  const [selectedMember, setSelectedMember] = useState<NetworkMember | null>(null);
  const [tab, setTab] = useState('tree');
  const [searchQuery, setSearchQuery] = useState('');
  const [filterLevel, setFilterLevel] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');
  
  const maxLevel = filterLevel === 'all' ? 8 : parseInt(filterLevel);
  
  const { data: stats, isLoading: statsLoading } = useNetworkStats();
  const { data: networkMembers, isLoading: membersLoading } = useNetworkTree(maxLevel);
  const { data: activities, isLoading: activitiesLoading } = useNetworkActivity({ limit: 50 });

  const filteredMembers = useMemo(() => {
    if (!networkMembers) return [];
    
    return networkMembers.filter(member => {
      const matchesSearch = !searchQuery || 
        member.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.email?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.referral_code.toLowerCase().includes(searchQuery.toLowerCase());
      
      const matchesLevel = filterLevel === 'all' || member.level === parseInt(filterLevel);
      
      const matchesStatus = filterStatus === 'all' ||
        (filterStatus === 'active' && (member.subscription_status === 'active' || member.monthly_activation_met)) ||
        (filterStatus === 'inactive' && member.subscription_status === 'inactive' && !member.monthly_activation_met) ||
        (filterStatus === 'frozen' && member.subscription_status === 'frozen');
      
      return matchesSearch && matchesLevel && matchesStatus;
    });
  }, [networkMembers, searchQuery, filterLevel, filterStatus]);

  const handleCopyLink = () => {
    const domain = window.location.origin;
    const referralLink = `${domain}/register`;
    navigator.clipboard.writeText(referralLink);
    toast.success("Реферальная ссылка скопирована!");
  };

  const handleShareLink = async () => {
    const domain = window.location.origin;
    const referralLink = `${domain}/register`;
    
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

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-3xl font-bold">Моя сеть</h1>
          <p className="text-muted-foreground mt-1">Управление партнёрской структурой</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" className="gap-2" onClick={handleExport}>
            <Download className="h-4 w-4" />
            Экспорт
          </Button>
          <Button className="gap-2" onClick={handleCopyLink}>
            <UserPlus className="h-4 w-4" />
            Пригласить партнёра
          </Button>
        </div>
      </div>

      {statsLoading ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
          {[...Array(8)].map((_, i) => (
            <Card key={i}><CardContent className="p-6"><Skeleton className="h-20" /></CardContent></Card>
          ))}
        </div>
      ) : stats && (
        <>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Всего партнёров</p><p className="text-2xl font-bold">{stats.total_partners}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Активных</p><p className="text-2xl font-bold text-success">{stats.active_partners}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Заморожено</p><p className="text-2xl font-bold text-warning">{stats.frozen_partners}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Уровней</p><p className="text-2xl font-bold">{stats.max_level}</p></CardContent></Card>
          </div>
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 mb-6">
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Новые партнёры</p><p className="text-2xl font-bold">{stats.new_this_month}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Активации</p><p className="text-2xl font-bold">{stats.activations_this_month}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Объём продаж</p><p className="text-2xl font-bold">${stats.volume_this_month.toFixed(0)}</p></CardContent></Card>
            <Card><CardContent className="p-6"><p className="text-sm text-muted-foreground">Комиссии</p><p className="text-2xl font-bold">${stats.commissions_this_month.toFixed(0)}</p></CardContent></Card>
          </div>
        </>
      )}

      <Card>
        <CardHeader>
          <Tabs value={tab} onValueChange={setTab}>
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="tree">Дерево структуры</TabsTrigger>
              <TabsTrigger value="list">Список партнёров</TabsTrigger>
              <TabsTrigger value="activity">Активность</TabsTrigger>
            </TabsList>

            <TabsContent value="tree" className="space-y-4">
              <div className="grid gap-4 md:grid-cols-3">
                <Input placeholder="Поиск..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
                <Select value={filterLevel} onValueChange={setFilterLevel}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Все уровни</SelectItem>
                    {[1,2,3,4,5,6,7,8].map(l => <SelectItem key={l} value={l.toString()}>{l} уровень</SelectItem>)}
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
              {membersLoading ? <Skeleton className="h-40" /> : <NetworkTree members={filteredMembers} />}
            </TabsContent>

            <TabsContent value="list">
              {membersLoading ? <Skeleton className="h-40" /> : filteredMembers.length === 0 ? (
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
              {activitiesLoading ? <Skeleton className="h-40" /> : !activities?.length ? (
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

      <Card><CardContent className="p-6"><div className="flex justify-between"><code className="text-sm">{window.location.origin}/register</code><div className="flex gap-2"><Button size="sm" onClick={handleCopyLink}><Copy className="h-4 w-4 mr-2" />Копировать</Button><Button size="sm" onClick={handleShareLink}><Share2 className="h-4 w-4 mr-2" />Поделиться</Button></div></div></CardContent></Card>
      
      <Dialog open={!!selectedMember} onOpenChange={() => setSelectedMember(null)}>
        <DialogContent><DialogHeader><DialogTitle>Карточка партнёра</DialogTitle></DialogHeader>{selectedMember && (<div className="space-y-4"><h3 className="font-semibold">{selectedMember.full_name}</h3><p className="text-sm">{selectedMember.email}</p></div>)}</DialogContent>
      </Dialog>
    </div>
  );
}
