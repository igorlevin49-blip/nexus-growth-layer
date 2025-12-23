import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow, TableFooter } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { toast } from "@/hooks/use-toast";
import { DollarSign, Search, History } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { formatCents } from "@/utils/formatMoney";
import { WithdrawalsHistory } from "@/components/Finances/WithdrawalsHistory";

interface Partner {
  id: string;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  available_cents: number;
  frozen_cents: number;
}

export default function AdminPayouts() {
  const { user, userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  
  const [partners, setPartners] = useState<Partner[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState("");
  const [payoutDialog, setPayoutDialog] = useState<{
    open: boolean;
    partner: Partner | null;
  }>({
    open: false,
    partner: null,
  });
  const [payoutForm, setPayoutForm] = useState({
    amount_cents: "",
    comment: "",
  });
  const [processing, setProcessing] = useState(false);

  // Debounce search query with longer delay
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearchQuery(searchQuery);
    }, 800);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  useEffect(() => {
    // Only search if query is empty or has at least 2 characters
    if (debouncedSearchQuery.trim() === '' || debouncedSearchQuery.trim().length >= 2) {
      fetchPartners();
    }
  }, [debouncedSearchQuery]);

  // Calculate totals
  const totals = partners.reduce(
    (acc, p) => ({
      available: acc.available + p.available_cents,
      frozen: acc.frozen + p.frozen_cents,
    }),
    { available: 0, frozen: 0 }
  );

  const fetchPartners = async () => {
    try {
      setLoading(true);
      
      // Use get_all_user_balances RPC for efficient batch balance fetching
      const { data: balancesData, error: balancesError } = await supabase.rpc('get_all_user_balances');
      
      if (balancesError) throw balancesError;
      
      // Create balances map
      const balancesMap = new Map<string, { available: number; frozen: number }>();
      (balancesData || []).forEach((b: any) => {
        balancesMap.set(b.user_id, {
          available: b.available_cents || 0,
          frozen: b.frozen_cents || 0,
        });
      });

      // Get profiles
      let query = supabase
        .from('profiles')
        .select('id, full_name, email, phone')
        .eq('is_active', true)
        .or('is_archived.is.null,is_archived.eq.false');

      if (debouncedSearchQuery.trim()) {
        const search = debouncedSearchQuery.trim();
        query = query.or(`email.ilike.%${search}%,full_name.ilike.%${search}%`);
      }

      // Limit results for performance
      const { data: profiles, error: profilesError } = await query
        .order('full_name', { ascending: true })
        .limit(100);

      if (profilesError) throw profilesError;

      if (!profiles || profiles.length === 0) {
        setPartners([]);
        setLoading(false);
        return;
      }

      // Combine profiles with balances (no N+1 queries!)
      const partnersWithBalances = profiles.map((profile) => {
        const balance = balancesMap.get(profile.id) || { available: 0, frozen: 0 };
        return {
          ...profile,
          available_cents: balance.available,
          frozen_cents: balance.frozen,
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
      setLoading(false);
    }
  };

  const openPayoutDialog = (partner: Partner) => {
    setPayoutDialog({ open: true, partner });
    setPayoutForm({ amount_cents: "", comment: "" });
  };

  const closePayoutDialog = () => {
    setPayoutDialog({ open: false, partner: null });
    setPayoutForm({ amount_cents: "", comment: "" });
  };

  const handlePayout = async () => {
    if (!payoutDialog.partner || !user) return;

    const amountCents = parseInt(payoutForm.amount_cents);
    
    // Validate amount
    if (isNaN(amountCents) || amountCents <= 0) {
      toast({
        title: "Ошибка",
        description: "Введите корректную сумму",
        variant: "destructive",
      });
      return;
    }

    // Check balance
    if (amountCents > payoutDialog.partner.available_cents) {
      toast({
        title: "Ошибка",
        description: `Недостаточно средств. Доступно: ${formatCents(payoutDialog.partner.available_cents, 'KZT')}`,
        variant: "destructive",
      });
      return;
    }

    // Validate comment
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
      // Call RPC function to process manual payout (bypasses RLS)
      const { data, error } = await supabase.rpc('process_manual_payout', {
        p_user_id: payoutDialog.partner.id,
        p_amount_cents: amountCents,
        p_comment: payoutForm.comment.trim()
      });

      if (error) throw error;

      const result = data as { success: boolean; error?: string; transaction_id?: string };

      if (!result.success) {
        const errorMessages: Record<string, string> = {
          'UNAUTHORIZED': 'Недостаточно прав для выполнения операции',
          'INVALID_AMOUNT': 'Некорректная сумма',
          'INSUFFICIENT_BALANCE': 'Недостаточно средств на балансе партнёра'
        };
        throw new Error(errorMessages[result.error || ''] || result.error);
      }

      toast({
        title: "Успешно",
        description: `Выплата ${formatCents(amountCents, 'KZT')} произведена`,
      });

      closePayoutDialog();
      fetchPartners(); // Refresh balances
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

  const PartnersTable = () => (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle>Ручные выплаты</CardTitle>
      </CardHeader>
      <CardContent>
        {/* Search Bar */}
        <div className="mb-4 flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Поиск по имени или email..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
        </div>

        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Партнёр</TableHead>
              <TableHead>Email</TableHead>
              <TableHead>Телефон</TableHead>
              <TableHead>Доступно</TableHead>
              <TableHead>Заморожено</TableHead>
              <TableHead className="text-right">Действия</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {partners.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-muted-foreground py-8">
                  Партнёры не найдены
                </TableCell>
              </TableRow>
            ) : (
              partners.map((partner) => (
                <TableRow key={partner.id}>
                  <TableCell>{partner.full_name || 'Без имени'}</TableCell>
                  <TableCell>{partner.email || '—'}</TableCell>
                  <TableCell>{partner.phone || '—'}</TableCell>
                  <TableCell>
                    <Badge variant="default" className="font-mono">
                      {formatCents(partner.available_cents, 'KZT')}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary" className="font-mono">
                      {formatCents(partner.frozen_cents, 'KZT')}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    {isSuperAdmin ? (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => openPayoutDialog(partner)}
                        disabled={partner.available_cents <= 0}
                      >
                        <DollarSign className="h-4 w-4 mr-1" />
                        Выдать
                      </Button>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
          {partners.length > 0 && (
            <TableFooter>
              <TableRow className="bg-muted/50 font-semibold">
                <TableCell colSpan={3}>Итого</TableCell>
                <TableCell>
                  <Badge variant="default" className="font-mono">
                    {formatCents(totals.available, 'KZT')}
                  </Badge>
                </TableCell>
                <TableCell>
                  <Badge variant="secondary" className="font-mono">
                    {formatCents(totals.frozen, 'KZT')}
                  </Badge>
                </TableCell>
                <TableCell></TableCell>
              </TableRow>
            </TableFooter>
          )}
        </Table>
      </CardContent>
    </Card>
  );

  if (loading) {
    return <div className="flex items-center justify-center h-96">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <Tabs defaultValue="payouts" className="space-y-4">
        <TabsList>
          <TabsTrigger value="payouts">
            <DollarSign className="h-4 w-4 mr-2" />
            Выплаты партнёрам
          </TabsTrigger>
          {isSuperAdmin && (
            <TabsTrigger value="history">
              <History className="h-4 w-4 mr-2" />
              История выплат
            </TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="payouts">
          <PartnersTable />
        </TabsContent>

        {isSuperAdmin && (
          <TabsContent value="history">
            <WithdrawalsHistory showExport showStats />
          </TabsContent>
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
                  {formatCents(payoutDialog.partner.available_cents, 'KZT')}
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="amount">Сумма выплаты (в тенге) *</Label>
                <Input
                  id="amount"
                  type="number"
                  min="1"
                  max={payoutDialog.partner.available_cents}
                  placeholder="Например: 55000 для 55 000 ₸"
                  value={payoutForm.amount_cents}
                  onChange={(e) => setPayoutForm(prev => ({ ...prev, amount_cents: e.target.value }))}
                />
                {payoutForm.amount_cents && !isNaN(parseInt(payoutForm.amount_cents)) && (
                  <p className="text-sm text-muted-foreground">
                    = {formatCents(parseInt(payoutForm.amount_cents), 'KZT')}
                  </p>
                )}
              </div>

              <div className="space-y-2">
                <Label htmlFor="comment">Основание / Комментарий *</Label>
                <Textarea
                  id="comment"
                  placeholder="Укажите причину выплаты (например: Выдача наличными в офисе)"
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
    </div>
  );
}