import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Search, Calendar } from "lucide-react";
import { formatCents } from "@/utils/formatMoney";
import { useAuth } from "@/hooks/useAuth";

interface Withdrawal {
  id: string;
  user_id: string;
  amount_cents: number;
  currency: string;
  status: string;
  created_at: string;
  payload: any;
  user?: {
    full_name: string | null;
    email: string | null;
  };
}

export function WithdrawalsHistory() {
  const { userRole } = useAuth();
  const isAdmin = userRole === 'admin' || userRole === 'superadmin';
  
  const [withdrawals, setWithdrawals] = useState<Withdrawal[]>([]);
  const [loading, setLoading] = useState(true);
  
  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [methodFilter, setMethodFilter] = useState("all"); // all, online, manual
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");

  useEffect(() => {
    fetchWithdrawals();
  }, [searchQuery, methodFilter, startDate, endDate]);

  const fetchWithdrawals = async () => {
    try {
      setLoading(true);

      // Build query
      let query = supabase
        .from('transactions')
        .select('*')
        .eq('type', 'withdrawal')
        .order('created_at', { ascending: false });

      // Apply date filters
      if (startDate) {
        query = query.gte('created_at', new Date(startDate).toISOString());
      }
      if (endDate) {
        const endDateTime = new Date(endDate);
        endDateTime.setHours(23, 59, 59, 999);
        query = query.lte('created_at', endDateTime.toISOString());
      }

      const { data: txData, error: txError } = await query;

      if (txError) throw txError;

      if (!txData || txData.length === 0) {
        setWithdrawals([]);
        setLoading(false);
        return;
      }

      // Apply method filter
      let filteredData = txData;
      if (methodFilter === 'manual') {
        filteredData = txData.filter(tx => {
          const payload = tx.payload as any;
          return payload?.manual_payout === true;
        });
      } else if (methodFilter === 'online') {
        filteredData = txData.filter(tx => {
          const payload = tx.payload as any;
          return !payload?.manual_payout;
        });
      }

      // For admins, fetch user details
      if (isAdmin) {
        const userIds = [...new Set(filteredData.map(tx => tx.user_id))];
        
        const { data: profiles, error: profilesError } = await supabase
          .from('profiles')
          .select('id, full_name, email')
          .in('id', userIds);

        if (profilesError) {
          console.error('Error fetching profiles:', profilesError);
        }

        const profilesMap = new Map(profiles?.map(p => [p.id, p]) || []);
        
        const withdrawalsWithUsers = filteredData.map(tx => ({
          ...tx,
          user: profilesMap.get(tx.user_id) || null
        }));

        // Apply search filter (admin only)
        if (searchQuery.trim()) {
          const search = searchQuery.toLowerCase();
          setWithdrawals(
            withdrawalsWithUsers.filter(w => 
              w.user?.full_name?.toLowerCase().includes(search) ||
              w.user?.email?.toLowerCase().includes(search)
            )
          );
        } else {
          setWithdrawals(withdrawalsWithUsers);
        }
      } else {
        setWithdrawals(filteredData);
      }
    } catch (error) {
      console.error('Error fetching withdrawals:', error);
    } finally {
      setLoading(false);
    }
  };

  const getMethodBadge = (withdrawal: Withdrawal) => {
    const payload = withdrawal.payload as any;
    if (payload?.manual_payout === true) {
      return <Badge variant="secondary">Выдано на кассе</Badge>;
    }
    return <Badge variant="default">Онлайн</Badge>;
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case "completed":
        return <Badge className="profit-indicator">Завершено</Badge>;
      case "processing":
        return <Badge className="pending-indicator">Обработка</Badge>;
      case "failed":
        return <Badge className="loss-indicator">Ошибка</Badge>;
      default:
        return <Badge variant="outline">Неизвестно</Badge>;
    }
  };

  return (
    <Card className="financial-card">
      <CardHeader>
        <CardTitle>История выплат</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Filters */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {isAdmin && (
            <div className="space-y-2">
              <Label htmlFor="search">Поиск партнёра</Label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  id="search"
                  placeholder="Имя или email..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-9"
                />
              </div>
            </div>
          )}
          
          <div className="space-y-2">
            <Label htmlFor="method">Способ выплаты</Label>
            <Select value={methodFilter} onValueChange={setMethodFilter}>
              <SelectTrigger id="method">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Все способы</SelectItem>
                <SelectItem value="online">Онлайн</SelectItem>
                <SelectItem value="manual">Выдано на кассе</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="startDate">Дата от</Label>
            <div className="relative">
              <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                id="startDate"
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="endDate">Дата до</Label>
            <div className="relative">
              <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                id="endDate"
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="pl-9"
              />
            </div>
          </div>
        </div>

        {/* Clear filters */}
        {(searchQuery || methodFilter !== 'all' || startDate || endDate) && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setSearchQuery("");
              setMethodFilter("all");
              setStartDate("");
              setEndDate("");
            }}
          >
            Сбросить фильтры
          </Button>
        )}

        {/* Results */}
        <div className="space-y-3">
          {loading ? (
            <p className="text-center text-muted-foreground py-8">Загрузка...</p>
          ) : withdrawals.length === 0 ? (
            <p className="text-center text-muted-foreground py-8">
              Выплаты не найдены
            </p>
          ) : (
            withdrawals.map((withdrawal) => (
              <div
                key={withdrawal.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between p-4 border border-border rounded-lg gap-3"
              >
                <div className="flex-1 space-y-2">
                  <div className="flex flex-wrap items-center gap-2">
                    {isAdmin && withdrawal.user && (
                      <span className="font-medium">
                        {withdrawal.user.full_name || 'Без имени'}
                      </span>
                    )}
                    {getMethodBadge(withdrawal)}
                    {getStatusBadge(withdrawal.status)}
                  </div>
                  
                  {isAdmin && withdrawal.user?.email && (
                    <p className="text-sm text-muted-foreground">
                      {withdrawal.user.email}
                    </p>
                  )}
                  
                  {(() => {
                    const payload = withdrawal.payload as any;
                    return payload?.comment && (
                      <p className="text-sm text-muted-foreground">
                        {payload.comment}
                      </p>
                    );
                  })()}
                  
                  <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
                    <span>ID: {withdrawal.id.substring(0, 8)}</span>
                    <span>{new Date(withdrawal.created_at).toLocaleString('ru-RU')}</span>
                    {(() => {
                      const payload = withdrawal.payload as any;
                      return payload?.admin_id && (
                        <span className="text-warning">
                          Выдано админом
                        </span>
                      );
                    })()}
                  </div>
                </div>
                
                <div className="text-right">
                  <div className="text-xl font-bold">
                    {formatCents(withdrawal.amount_cents, withdrawal.currency)}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </CardContent>
    </Card>
  );
}
