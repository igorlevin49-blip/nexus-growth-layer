import { useState, useEffect, useMemo, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import { DollarSign, History, Users, TrendingUp, TrendingDown } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { formatKZT } from "@/utils/formatMoney";
import { WithdrawalsHistory } from "@/components/Finances/WithdrawalsHistory";
import { PartnersTable, Partner, BalanceFilter } from "@/components/Admin/PartnersTable";

export default function AdminPayouts() {
  const { user, userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  
  const [partners, setPartners] = useState<Partner[]>([]);
  const [initialLoading, setInitialLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState("");
  const [balanceFilter, setBalanceFilter] = useState<BalanceFilter>("all");
  const requestIdRef = useRef(0);
  
  const [payoutDialog, setPayoutDialog] = useState<{
    open: boolean;
    partner: Partner | null;
  }>({
    open: false,
    partner: null,
  });
  const [payoutForm, setPayoutForm] = useState({
    amount_kzt: "",
    comment: "",
  });
  const [processing, setProcessing] = useState(false);

  // Adjustment dialog state
  const [adjustmentDialog, setAdjustmentDialog] = useState<{
    open: boolean;
    partner: Partner | null;
  }>({
    open: false,
    partner: null,
  });
  const [adjustmentForm, setAdjustmentForm] = useState({
    amount: "",
    direction: "credit" as "credit" | "debit",
    reason: "",
  });

  // Debounce search query
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearchQuery(searchQuery);
    }, 800);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  useEffect(() => {
    if (debouncedSearchQuery.trim() === '' || debouncedSearchQuery.trim().length >= 2) {
      fetchPartners(initialLoading ? 'initial' : 'refresh');
    }
  }, [debouncedSearchQuery]);

  // Filter partners based on balance filter
  const filteredPartners = useMemo(() => {
    switch (balanceFilter) {
      case "has_payout":
        return partners.filter(p => p.available_kzt > 0);
      case "no_payout":
        return partners.filter(p => p.available_kzt <= 0 && p.available_kzt >= 0);
      case "negative":
        return partners.filter(p => p.available_kzt < 0);
      default:
        return partners;
    }
  }, [partners, balanceFilter]);

  // Calculate totals
  const totals = useMemo(() => ({
    available: filteredPartners.reduce((acc, p) => acc + p.available_kzt, 0),
    frozen: filteredPartners.reduce((acc, p) => acc + p.frozen_kzt, 0),
  }), [filteredPartners]);

  // Stats for filter badges
  const stats = useMemo(() => ({
    all: partners.length,
    has_payout: partners.filter(p => p.available_kzt > 0).length,
    no_payout: partners.filter(p => p.available_kzt <= 0 && p.available_kzt >= 0).length,
    negative: partners.filter(p => p.available_kzt < 0).length,
  }), [partners]);

  const fetchPartners = async (mode: 'initial' | 'refresh' = 'initial') => {
    const currentRequestId = ++requestIdRef.current;
    
    try {
      if (mode === 'initial') {
        setInitialLoading(true);
      } else {
        setIsRefreshing(true);
      }
      
      const { data: balancesData, error: balancesError } = await supabase.rpc('get_all_user_balances');
      
      if (balancesError) throw balancesError;
      
      // Check if this request is still current
      if (currentRequestId !== requestIdRef.current) return;
      
      const balancesMap = new Map<string, { available: number; frozen: number }>();
      (balancesData || []).forEach((b: any) => {
        balancesMap.set(b.user_id, {
          available: Number(b?.available_kzt ?? b?.available_cents ?? 0),
          frozen: Number(b?.frozen_kzt ?? b?.frozen_cents ?? 0),
        });
      });

      let query = supabase
        .from('profiles')
        .select('id, full_name, email, phone')
        .eq('is_active', true)
        .or('is_archived.is.null,is_archived.eq.false');

      if (debouncedSearchQuery.trim()) {
        const search = debouncedSearchQuery.trim();
        query = query.or(`email.ilike.%${search}%,full_name.ilike.%${search}%`);
      }

      const { data: profiles, error: profilesError } = await query
        .order('full_name', { ascending: true })
        .limit(500);

      if (profilesError) throw profilesError;
      
      // Check again if this request is still current
      if (currentRequestId !== requestIdRef.current) return;

      if (!profiles || profiles.length === 0) {
        setPartners([]);
        return;
      }

      const partnersWithBalances = profiles.map((profile) => {
        const balance = balancesMap.get(profile.id) || { available: 0, frozen: 0 };
        return {
          ...profile,
          available_kzt: balance.available,
          frozen_kzt: balance.frozen,
        };
      });

      setPartners(partnersWithBalances);
    } catch (error) {
      console.error('Error fetching partners:', error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить партнёров",
        variant: "destructive",
      });
    } finally {
      if (currentRequestId === requestIdRef.current) {
        setInitialLoading(false);
        setIsRefreshing(false);
      }
    }
  };

  const openPayoutDialog = (partner: Partner) => {
    setPayoutDialog({ open: true, partner });
    setPayoutForm({ amount_kzt: "", comment: "" });
  };

  const closePayoutDialog = () => {
    setPayoutDialog({ open: false, partner: null });
    setPayoutForm({ amount_kzt: "", comment: "" });
  };

  const openAdjustmentDialog = (partner: Partner) => {
    setAdjustmentDialog({ open: true, partner });
    setAdjustmentForm({ 
      amount: "", 
      direction: partner.available_kzt < 0 ? "credit" : "debit",
      reason: partner.available_kzt < 0 ? "Коррекция отрицательного баланса" : ""
    });
  };

  const closeAdjustmentDialog = () => {
    setAdjustmentDialog({ open: false, partner: null });
    setAdjustmentForm({ amount: "", direction: "credit", reason: "" });
  };

  const handlePayout = async () => {
    if (!payoutDialog.partner || !user) return;

    const amountKzt = parseInt(payoutForm.amount_kzt);
    
    if (isNaN(amountKzt) || amountKzt <= 0) {
      toast({
        title: "Ошибка",
        description: "Введите корректную сумму",
        variant: "destructive",
      });
      return;
    }

    if (amountKzt > payoutDialog.partner.available_kzt) {
      toast({
        title: "Ошибка",
        description: `Недостаточно средств. Доступно: ${formatKZT(payoutDialog.partner.available_kzt, 'KZT')}`,
        variant: "destructive",
      });
      return;
    }

    if (!payoutForm.comment.trim()) {
      toast({
        title: "Ошибка",
        description: "Укажите основание для выплаты",
        variant: "destructive",
      });
      return;
    }

    setProcessing(true);

    try {
      const { data, error } = await supabase.rpc('process_manual_payout', {
        p_user_id: payoutDialog.partner.id,
        p_amount_cents: amountKzt, // В тенге (KZT), параметр RPC ещё называется _cents
        p_comment: payoutForm.comment.trim()
      });

      if (error) throw error;

      const result = data as { success: boolean; error?: string };

      if (!result.success) {
        throw new Error(result.error || 'Неизвестная ошибка');
      }

      toast({
        title: "Успешно",
        description: `Выплата ${formatKZT(amountKzt, 'KZT')} произведена`,
      });

      closePayoutDialog();
      fetchPartners('refresh');
    } catch (error: any) {
      console.error('Payout error:', error);
      toast({
        title: "Ошибка",
        description: error.message || "Не удалось произвести выплату",
        variant: "destructive",
      });
    } finally {
      setProcessing(false);
    }
  };

  const handleAdjustment = async () => {
    if (!adjustmentDialog.partner || !user) return;

    const amountKzt = parseInt(adjustmentForm.amount);
    
    if (isNaN(amountKzt) || amountKzt <= 0) {
      toast({
        title: "Ошибка",
        description: "Введите корректную сумму",
        variant: "destructive",
      });
      return;
    }

    if (!adjustmentForm.reason.trim() || adjustmentForm.reason.trim().length < 3) {
      toast({
        title: "Ошибка",
        description: "Укажите причину корректировки (минимум 3 символа)",
        variant: "destructive",
      });
      return;
    }

    setProcessing(true);

    try {
      // Amount in whole KZT (no cents conversion for KZT)
      const amountKztSigned = adjustmentForm.direction === "credit" 
        ? amountKzt 
        : -amountKzt;

      const { data, error } = await supabase.rpc('admin_adjust_balance' as any, {
        p_user_id: adjustmentDialog.partner.id,
        p_amount_kzt: amountKztSigned,
        p_reason: adjustmentForm.reason.trim(),
        p_admin_id: user.id
      });

      if (error) throw error;

      const result = data as { success: boolean; error?: string };

      if (!result.success) {
        const errorMessages: Record<string, string> = {
          'UNAUTHORIZED': 'Недостаточно прав',
          'ZERO_AMOUNT': 'Сумма не может быть нулевой',
          'REASON_REQUIRED': 'Укажите причину',
          'USER_NOT_FOUND': 'Пользователь не найден'
        };
        throw new Error(errorMessages[result.error || ''] || result.error);
      }

      toast({
        title: "Успешно",
        description: adjustmentForm.direction === "credit" 
          ? `Начислено ${amountKzt} ₸`
          : `Списано ${amountKzt} ₸`,
      });

      closeAdjustmentDialog();
      fetchPartners('refresh');
    } catch (error: any) {
      console.error('Adjustment error:', error);
      toast({
        title: "Ошибка",
        description: error.message || "Не удалось выполнить корректировку",
        variant: "destructive",
      });
    } finally {
      setProcessing(false);
    }
  };


  if (initialLoading) {
    return <div className="flex items-center justify-center h-96">Загрузка...</div>;
  }

  return (
    <div className="p-4 md:p-8">
      <Tabs defaultValue="payouts" className="space-y-4">
        <TabsList className="flex-wrap h-auto gap-1">
          <TabsTrigger value="payouts" className="gap-2">
            <DollarSign className="h-4 w-4" />
            <span className="hidden sm:inline">Выплаты</span>
          </TabsTrigger>
          {isSuperAdmin && (
            <>
              <TabsTrigger value="history" className="gap-2">
                <History className="h-4 w-4" />
                <span className="hidden sm:inline">История</span>
              </TabsTrigger>
              <TabsTrigger value="all" className="gap-2">
                <Users className="h-4 w-4" />
                <span className="hidden sm:inline">Все партнёры</span>
              </TabsTrigger>
            </>
          )}
        </TabsList>

        <TabsContent value="payouts">
          <PartnersTable
            partners={partners}
            filteredPartners={filteredPartners}
            totals={totals}
            stats={stats}
            searchQuery={searchQuery}
            onSearchChange={setSearchQuery}
            balanceFilter={balanceFilter}
            onBalanceFilterChange={setBalanceFilter}
            isRefreshing={isRefreshing}
            isSuperAdmin={isSuperAdmin}
            onOpenPayoutDialog={openPayoutDialog}
            onOpenAdjustmentDialog={openAdjustmentDialog}
          />
        </TabsContent>

        {isSuperAdmin && (
          <>
            <TabsContent value="history">
              <WithdrawalsHistory showExport showStats />
            </TabsContent>
            <TabsContent value="all">
              <PartnersTable
                partners={partners}
                filteredPartners={filteredPartners}
                totals={totals}
                stats={stats}
                searchQuery={searchQuery}
                onSearchChange={setSearchQuery}
                balanceFilter={balanceFilter}
                onBalanceFilterChange={setBalanceFilter}
                isRefreshing={isRefreshing}
                isSuperAdmin={isSuperAdmin}
                onOpenPayoutDialog={openPayoutDialog}
                onOpenAdjustmentDialog={openAdjustmentDialog}
                showActions={false}
              />
            </TabsContent>
          </>
        )}
      </Tabs>

      {/* Payout Dialog */}
      <Dialog open={payoutDialog.open} onOpenChange={(open) => !open && closePayoutDialog()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ручная выплата</DialogTitle>
          </DialogHeader>
          {payoutDialog.partner && (
            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Партнёр</p>
                <p className="font-medium">{payoutDialog.partner.full_name || 'Без имени'}</p>
                <p className="text-sm text-muted-foreground">{payoutDialog.partner.email}</p>
              </div>
              
              <div>
                <p className="text-sm text-muted-foreground">Доступно для выплаты</p>
                <p className="text-lg font-bold text-primary">
                  {formatKZT(payoutDialog.partner.available_kzt, 'KZT')}
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="amount">Сумма выплаты (в тенге) *</Label>
                <Input
                  id="amount"
                  type="number"
                  min="1"
                  max={payoutDialog.partner.available_kzt}
                  placeholder="Например: 55000"
                  value={payoutForm.amount_kzt}
                  onChange={(e) => setPayoutForm(prev => ({ ...prev, amount_kzt: e.target.value }))}
                />
                {payoutForm.amount_kzt && !isNaN(parseInt(payoutForm.amount_kzt)) && (
                  <p className="text-sm text-muted-foreground">
                    = {formatKZT(parseInt(payoutForm.amount_kzt), 'KZT')}
                  </p>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor="comment">Основание / Комментарий *</Label>
                <Textarea
                  id="comment"
                  placeholder="Укажите причину выплаты"
                  value={payoutForm.comment}
                  onChange={(e) => setPayoutForm(prev => ({ ...prev, comment: e.target.value }))}
                  rows={3}
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={closePayoutDialog} disabled={processing}>
              Отмена
            </Button>
            <Button onClick={handlePayout} disabled={processing}>
              {processing ? "Обработка..." : "Подтвердить выплату"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Adjustment Dialog */}
      <Dialog open={adjustmentDialog.open} onOpenChange={(open) => !open && closeAdjustmentDialog()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Корректировка баланса</DialogTitle>
          </DialogHeader>
          {adjustmentDialog.partner && (
            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground">Партнёр</p>
                <p className="font-medium">{adjustmentDialog.partner.full_name || 'Без имени'}</p>
                <p className="text-sm text-muted-foreground">{adjustmentDialog.partner.email}</p>
              </div>
              
              <div>
                <p className="text-sm text-muted-foreground">Текущий баланс</p>
                <p className={`text-lg font-bold ${adjustmentDialog.partner.available_kzt < 0 ? 'text-destructive' : 'text-primary'}`}>
                  {formatKZT(adjustmentDialog.partner.available_kzt, 'KZT')}
                </p>
              </div>

              <div className="space-y-2">
                <Label>Тип операции</Label>
                <Select 
                  value={adjustmentForm.direction} 
                  onValueChange={(v) => setAdjustmentForm(prev => ({ ...prev, direction: v as "credit" | "debit" }))}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="credit">
                      <div className="flex items-center gap-2">
                        <TrendingUp className="h-4 w-4 text-green-500" />
                        Начислить (увеличить баланс)
                      </div>
                    </SelectItem>
                    <SelectItem value="debit">
                      <div className="flex items-center gap-2">
                        <TrendingDown className="h-4 w-4 text-destructive" />
                        Списать (уменьшить баланс)
                      </div>
                    </SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="adj-amount">Сумма (в тенге) *</Label>
                <Input
                  id="adj-amount"
                  type="number"
                  min="1"
                  placeholder="Например: 1000"
                  value={adjustmentForm.amount}
                  onChange={(e) => setAdjustmentForm(prev => ({ ...prev, amount: e.target.value }))}
                />
                {adjustmentForm.amount && !isNaN(parseInt(adjustmentForm.amount)) && (
                  <p className="text-sm text-muted-foreground">
                    Новый баланс: {formatKZT(
                      adjustmentDialog.partner.available_kzt + 
                      (adjustmentForm.direction === "credit" ? 1 : -1) * parseInt(adjustmentForm.amount), 
                      'KZT'
                    )}
                  </p>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor="adj-reason">Причина корректировки *</Label>
                <Textarea
                  id="adj-reason"
                  placeholder="Укажите причину"
                  value={adjustmentForm.reason}
                  onChange={(e) => setAdjustmentForm(prev => ({ ...prev, reason: e.target.value }))}
                  rows={3}
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={closeAdjustmentDialog} disabled={processing}>
              Отмена
            </Button>
            <Button 
              onClick={handleAdjustment} 
              disabled={processing}
              variant={adjustmentForm.direction === "debit" ? "destructive" : "default"}
            >
              {processing ? "Обработка..." : adjustmentForm.direction === "credit" ? "Начислить" : "Списать"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
