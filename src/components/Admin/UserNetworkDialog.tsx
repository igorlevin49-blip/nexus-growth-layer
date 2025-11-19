import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useNetworkTree } from "@/hooks/useNetworkTree";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { Loader2, Users } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";

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
  const { data: members, isLoading } = useNetworkTree(10);
  
  // Filter to show only members for this specific user
  const userMembers = members?.filter(m => m.user_id === userId) || [];
  
  // Calculate statistics by level
  const statsByLevel = userMembers.reduce((acc, member) => {
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

  const totalPartners = userMembers.length;
  const maxLevel = Math.max(...Object.keys(statsByLevel).map(Number), 0);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-6xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Структура партнёров</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
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
                  <p className="text-sm text-muted-foreground">Всего партнёров</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Statistics by Level */}
          {maxLevel > 0 && (
            <Card>
              <CardContent className="pt-6">
                <h4 className="font-semibold mb-4">Статистика по уровням</h4>
                <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                  {Array.from({ length: maxLevel }, (_, i) => i + 1).map(level => {
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
            ) : userMembers.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">
                У пользователя пока нет партнёров
              </div>
            ) : (
              <NetworkTree members={userMembers} />
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
