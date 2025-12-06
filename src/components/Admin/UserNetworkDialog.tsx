import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { Loader2, Users, ShoppingBag } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { NetworkMember } from "@/hooks/useNetworkTree";

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
  
  // Dynamic max levels based on structure type
  const maxLevelForStructure = structureType === 1 ? 5 : 10;

  const { data: members, isLoading } = useQuery({
    queryKey: ['admin-network-tree', userId, structureType],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: userId,
        max_level: maxLevelForStructure,
        p_structure_type: structureType
      });

      if (error) throw error;
      
      // Map the data to include parent_partner_id
      return ((data || []) as Array<{
        user_id: string;
        partner_id: string;
        level: number;
        full_name: string | null;
        email: string | null;
        avatar_url: string | null;
        subscription_status: string | null;
        monthly_activation_met: boolean | null;
        referral_code: string;
        created_at: string;
        direct_referrals: number;
        total_team: number;
        monthly_volume: number;
        parent_partner_id: string | null;
      }>) as NetworkMember[];
    },
    enabled: open && !!userId,
  });
  
  // Calculate statistics by level
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
  const displayLevels = Math.min(Math.max(...Object.keys(statsByLevel).map(Number), 0), maxLevelForStructure);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Структура партнёров</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* Structure Selector */}
          <Tabs value={structureType.toString()} onValueChange={(v) => setStructureType(parseInt(v) as 1 | 2)}>
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
                <div className="text-right">
                  <div className="flex items-center gap-2 text-2xl font-bold">
                    <Users className="h-6 w-6" />
                    {totalPartners}
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Партнёров (L1-L{maxLevelForStructure})
                  </p>
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
                    return (
                      <div key={level} className="border rounded-lg p-3">
                        <div className="text-sm font-medium mb-2">Уровень {level}</div>
                        <div className="text-2xl font-bold mb-1">{stats.count}</div>
                        <div className="flex gap-2 text-xs">
                          <Badge variant="default" className="profit-indicator">
                            {stats.active} акт.
                          </Badge>
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

          {/* Network Tree */}
          <div>
            <h4 className="font-semibold mb-4">Дерево партнёров</h4>
            {isLoading ? (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
              </div>
            ) : !members || members.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">
                У пользователя пока нет партнёров в этой структуре
              </div>
            ) : (
              <NetworkTree members={members} />
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
