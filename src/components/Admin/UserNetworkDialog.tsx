import { useState, useMemo, useCallback } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { Users, ShoppingBag, AlertTriangle, AlertCircle, DollarSign, X, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { NetworkMember } from "@/hooks/useNetworkTree";
import { UserCommissionAuditDialog } from "./UserCommissionAuditDialog";

interface UserNetworkDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  userName: string;
  userEmail: string;
}

export function UserNetworkDialog({ 
  open, 
  onOpenChange, 
  userId, 
  userName,
  userEmail 
}: UserNetworkDialogProps) {
  const [structureType, setStructureType] = useState<1 | 2>(1);
  const [auditDialogOpen, setAuditDialogOpen] = useState(false);
  
  // Filter states
  const [searchQuery, setSearchQuery] = useState('');
  const [filterLevel, setFilterLevel] = useState('all');
  const [filterStatus, setFilterStatus] = useState('all');
  const [filterCommission, setFilterCommission] = useState<'all' | 'with_commission' | 'without_commission'>('all');
  
  // Dynamic max levels based on structure type
  const maxLevelForStructure = structureType === 1 ? 5 : 10;

  // Type matching the get_referral_network_from_table function return
  interface NetworkMemberRaw {
    user_id: string;
    partner_id: string;
    email: string | null;
    full_name: string | null;
    referral_code: string;
    subscription_status: string | null;
    monthly_activation_met: boolean;
    level: number;
    structure_type: number;
    created_at: string | null;
    has_commission_received: boolean;
    no_commission_reason: string | null;
    parent_partner_id: string | null;
  }

  // Map raw DB response to NetworkMember interface
  const mapToNetworkMember = (raw: NetworkMemberRaw): NetworkMember => ({
    user_id: raw.user_id,
    partner_id: raw.partner_id || raw.user_id,
    level: raw.level,
    full_name: raw.full_name,
    email: raw.email,
    phone: null,
    avatar_url: null,
    subscription_status: raw.subscription_status,
    subscription_expires_at: null,
    monthly_activation_met: raw.monthly_activation_met,
    referral_code: raw.referral_code || '',
    created_at: raw.created_at || '',
    direct_referrals: 0,
    total_team: 0,
    monthly_volume: 0,
    parent_partner_id: raw.parent_partner_id,
    parent_user_id: null,
    has_commission_received: raw.has_commission_received,
    no_commission_reason: raw.no_commission_reason,
    commission_status: raw.has_commission_received ? 'received' : null,
    commission_frozen_until: null,
  });

  const { data: members, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: ['admin-network-tree', userId, structureType],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: userId,
        p_max_levels: maxLevelForStructure,
        p_structure_type: structureType,
      });

      if (error) {
        console.error('[UserNetworkDialog] RPC error', {
          userId,
          structureType,
          maxLevelForStructure,
          error,
        });
        throw error;
      }

      const rawMembers = (data || []) as NetworkMemberRaw[];
      const result = rawMembers.map(mapToNetworkMember);
      console.log('[UserNetworkDialog] Loaded members', {
        userId,
        structureType,
        count: result.length,
      });

      return result;
    },
    enabled: open && !!userId,
    refetchOnWindowFocus: true,
  });

  // Filter members based on search and filter criteria
  const filteredMembers = useMemo(() => {
    if (!members) return [];
    
    return members.filter(member => {
      const matchesSearch = !searchQuery || 
        member.full_name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.email?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.referral_code?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        member.phone?.toLowerCase().includes(searchQuery.toLowerCase());
      
      const matchesLevel = filterLevel === 'all' || member.level === parseInt(filterLevel);
      
      const matchesStatus = filterStatus === 'all' ||
        (filterStatus === 'active' && (member.subscription_status === 'active' || member.monthly_activation_met)) ||
        (filterStatus === 'inactive' && member.subscription_status === 'inactive' && !member.monthly_activation_met) ||
        (filterStatus === 'frozen' && member.subscription_status === 'frozen');

      const matchesCommission = structureType !== 1 || filterCommission === 'all' ||
        (filterCommission === 'with_commission' && member.has_commission_received === true) ||
        (filterCommission === 'without_commission' && member.has_commission_received === false);
      
      return matchesSearch && matchesLevel && matchesStatus && matchesCommission;
    });
  }, [members, searchQuery, filterLevel, filterStatus, structureType, filterCommission]);

  // Level options
  const levelOptions = useMemo(() => 
    Array.from({ length: maxLevelForStructure }, (_, i) => i + 1),
    [maxLevelForStructure]
  );

  // Check if any filter is active
  const hasActiveFilters = searchQuery || filterLevel !== 'all' || filterStatus !== 'all' || filterCommission !== 'all';

  // Reset all filters
  const resetFilters = useCallback(() => {
    setSearchQuery('');
    setFilterLevel('all');
    setFilterStatus('all');
    setFilterCommission('all');
  }, []);

  // Reset filters when structure type changes
  const handleStructureChange = useCallback((value: string) => {
    setStructureType(parseInt(value) as 1 | 2);
    resetFilters();
  }, [resetFilters]);
  
  // Calculate statistics by level from ALL members (not filtered)
  const statsByLevel = (members || []).reduce((acc, member) => {
    if (!acc[member.level]) {
      acc[member.level] = { count: 0, active: 0, frozen: 0 };
    }
    acc[member.level].count++;
    if (member.subscription_status === 'active' || member.monthly_activation_met) {
      acc[member.level].active++;
    } else if (member.subscription_status === 'frozen') {
      acc[member.level].frozen++;
    }
    return acc;
  }, {} as Record<number, { count: number; active: number; frozen: number }>);

  const totalPartners = (members || []).length;
  const totalActivePartners = (members || []).filter(m => m.subscription_status === 'active' || m.monthly_activation_met).length;
  const displayLevels = Math.min(Math.max(...Object.keys(statsByLevel).map(Number), 0), maxLevelForStructure);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Структура партнёров</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Structure Selector */}
          <Tabs value={structureType.toString()} onValueChange={handleStructureChange}>
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="1" className="flex items-center gap-2">
                <Users className="h-4 w-4" />
                <span>Структура 1 (L1-L5)</span>
              </TabsTrigger>
              <TabsTrigger value="2" className="flex items-center gap-2">
                <ShoppingBag className="h-4 w-4" />
                <span>Структура 2 (L1-L10)</span>
              </TabsTrigger>
            </TabsList>
          </Tabs>

          {/* User Info */}
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-lg font-semibold">{userName}</h3>
                  <p className="text-sm text-muted-foreground">{userEmail}</p>
                  <p className="text-xs text-muted-foreground">ID: {userId}</p>
                </div>
                <div className="text-right space-y-2">
                  <div className="flex items-center gap-2 text-2xl font-bold">
                    <Users className="h-6 w-6" />
                    {totalActivePartners}
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Активных партнёров (L1-L{maxLevelForStructure})
                    {totalPartners > totalActivePartners && (
                      <span className="block text-xs">+ {totalPartners - totalActivePartners} ожидают активации</span>
                    )}
                  </p>
                  {structureType === 1 && (
                    <Button 
                      variant="outline" 
                      size="sm" 
                      onClick={() => setAuditDialogOpen(true)}
                      className="gap-1"
                    >
                      <AlertTriangle className="h-4 w-4" />
                      Аудит комиссий S1
                    </Button>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Statistics by Level */}
          {displayLevels > 0 && (
            <Card>
              <CardContent className="pt-6">
                <h4 className="font-semibold mb-4">Статистика по уровням (L1-L{maxLevelForStructure})</h4>
                <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                  {Array.from({ length: maxLevelForStructure }, (_, i) => i + 1).map(level => {
                    const stats = statsByLevel[level] || { count: 0, active: 0, frozen: 0 };
                    const pending = stats.count - stats.active - stats.frozen;
                    return (
                      <div key={level} className="border rounded-lg p-3">
                        <div className="text-sm font-medium mb-2">Уровень {level}</div>
                        <div className="text-2xl font-bold mb-1">{stats.active}</div>
                        <div className="flex flex-wrap gap-1 text-xs">
                          {pending > 0 && (
                            <Badge variant="outline" className="text-muted-foreground">
                              {pending} ожид.
                            </Badge>
                          )}
                          {stats.frozen > 0 && (
                            <Badge variant="secondary" className="pending-indicator">
                              {stats.frozen} зам.
                            </Badge>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          )}

          {/* Filters Section */}
          <Card>
            <CardContent className="pt-6 space-y-4">
              <h4 className="font-semibold">Фильтры</h4>
              
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
                </div>
              )}

              {/* Search and Dropdowns */}
              <div className="grid gap-4 md:grid-cols-4">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input 
                    placeholder="Поиск по имени, email, телефону..." 
                    value={searchQuery} 
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="pl-9"
                  />
                </div>
                <select
                  value={filterLevel}
                  onChange={(e) => setFilterLevel(e.target.value)}
                  className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <option value="all">Все уровни</option>
                  {levelOptions.map(l => (
                    <option key={l} value={l.toString()}>Уровень {l}</option>
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
                  <option value="inactive">Ожидают активации</option>
                </select>
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

              {/* Results counter and reset */}
              <div className="flex items-center justify-between">
                <p className="text-sm text-muted-foreground">
                  Показано: <span className="font-semibold">{filteredMembers.length}</span> из <span className="font-semibold">{totalPartners}</span>
                </p>
                {hasActiveFilters && (
                  <Button variant="ghost" size="sm" onClick={resetFilters} className="gap-1">
                    <X className="h-4 w-4" />
                    Сбросить фильтры
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Network Tree */}
          <div>
            <h4 className="font-semibold mb-4">Дерево партнёров</h4>
            {isLoading ? null : error ? (
              <div className="flex flex-col items-center justify-center gap-3 py-8 text-muted-foreground">
                <div>Не удалось загрузить структуру партнёров</div>
                <Button variant="outline" size="sm" onClick={() => refetch()}>
                  Повторить
                </Button>
              </div>
            ) : !filteredMembers || filteredMembers.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">
                {hasActiveFilters ? 
                  'Нет партнёров, соответствующих фильтрам' : 
                  'У пользователя пока нет партнёров в этой структуре'
                }
              </div>
            ) : filterLevel !== 'all' ? (
              // Flat list when specific level is selected
              <div className="space-y-2">
                {filteredMembers.map(member => (
                  <Card key={member.partner_id} className="p-4">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-medium">{member.full_name || 'Без имени'}</p>
                        <p className="text-sm text-muted-foreground">{member.email}</p>
                        {member.phone && <p className="text-sm text-muted-foreground">{member.phone}</p>}
                      </div>
                      <div className="flex items-center gap-2">
                        <Badge variant="outline">L{member.level}</Badge>
                        {member.subscription_status === 'active' || member.monthly_activation_met ? (
                          <Badge className="profit-indicator">Активен</Badge>
                        ) : member.subscription_status === 'frozen' ? (
                          <Badge className="pending-indicator">Заморожен</Badge>
                        ) : (
                          <Badge className="frozen-indicator">Ожидает</Badge>
                        )}
                        {structureType === 1 && member.has_commission_received === false && member.no_commission_reason && (
                          <Badge variant="secondary" className="bg-warning text-warning-foreground">
                            Без начисления
                          </Badge>
                        )}
                      </div>
                    </div>
                  </Card>
                ))}
              </div>
            ) : (
              <NetworkTree members={filteredMembers} />
            )}
          </div>
        </div>

        {/* Commission Audit Dialog */}
        <UserCommissionAuditDialog
          open={auditDialogOpen}
          onOpenChange={setAuditDialogOpen}
          userId={userId}
          userName={userName}
        />
      </DialogContent>
    </Dialog>
  );
}
