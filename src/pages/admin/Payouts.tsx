import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { DollarSign, Search } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { formatCents } from "@/utils/formatMoney";

interface Partner {
  id: string;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  available_cents: number;
  frozen_cents: number;
}

export default function AdminPayouts() {
  const { user } = useAuth();
  const [partners, setPartners] = useState<Partner[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
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

  useEffect(() => {
    fetchPartners();
  }, [searchQuery]);

  const fetchPartners = async () => {
    try {
      setLoading(true);
      
      // Get all profiles with balances
      let query = supabase
        .from('profiles')
        .select('id, full_name, email, phone')
        .eq('is_active', true)
        .or('is_archived.is.null,is_archived.eq.false');

      if (searchQuery.trim()) {
        const search = searchQuery.trim();
        query = query.or(`email.ilike.%${search}%,full_name.ilike.%${search}%`);
      }

      const { data: profiles, error: profilesError } = await query.order('full_name', { ascending: true });

      if (profilesError) throw profilesError;

      if (!profiles || profiles.length === 0) {
        setPartners([]);
        setLoading(false);
        return;
      }

      // Get balances for all users
      const balancePromises = profiles.map(async (profile) => {
        const { data: balanceData, error: balanceError } = await supabase.rpc('get_user_balance', {
          p_user_id: profile.id
        });

        if (balanceError) {
          console.error('Balance error for user', profile.id, balanceError);
          return {
            ...profile,
            available_cents: 0,
            frozen_cents: 0,
          };
        }

        const balance = balanceData?.[0] || { available_cents: 0, frozen_cents: 0 };
        return {
          ...profile,
          available_cents: balance.available_cents || 0,
          frozen_cents: balance.frozen_cents || 0,
        };
      });

      const partnersWithBalances = await Promise.all(balancePromises);
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
        description: `Недостаточно средств. Доступно: ${formatCents(payoutDialog.partner.available_cents, 'USD')}`,
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
      // Create withdrawal transaction
      const { error: transactionError } = await supabase
        .from('transactions')
        .insert({
          user_id: payoutDialog.partner.id,
          type: 'withdrawal',
          amount_cents: amountCents,
          status: 'completed',
          currency: 'USD',
          payload: {
            manual_payout: true,
            admin_id: user.id,
            comment: payoutForm.comment.trim(),
            processed_at: new Date().toISOString(),
          }
        });

      if (transactionError) throw transactionError;

      // Log admin action
      const { error: auditError } = await supabase
        .from('admin_audit')
        .insert({
          admin_id: user.id,
          action_type: 'manual_payout',
          target_type: 'user',
          target_id: payoutDialog.partner.id,
          comment: payoutForm.comment.trim(),
          metadata: {
            amount_cents: amountCents,
            partner_name: payoutDialog.partner.full_name,
            partner_email: payoutDialog.partner.email,
          }
        });

      if (auditError) {
        console.error('Audit log error:', auditError);
        // Don't block the operation
      }

      toast({
        title: "Успешно",
        description: `Выплата ${formatCents(amountCents, 'USD')} произведена`,
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

  if (loading) {
    return <div className="flex items-center justify-center h-96">Загрузка...</div>;
  }

  return (
    <div className="p-8">
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
                        {formatCents(partner.available_cents, 'USD')}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="font-mono">
                        {formatCents(partner.frozen_cents, 'USD')}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => openPayoutDialog(partner)}
                        disabled={partner.available_cents <= 0}
                      >
                        <DollarSign className="h-4 w-4 mr-1" />
                        Выдать
                      </Button>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

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
                  {formatCents(payoutDialog.partner.available_cents, 'USD')}
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="amount">Сумма выплаты (в центах) *</Label>
                <Input
                  id="amount"
                  type="number"
                  min="1"
                  max={payoutDialog.partner.available_cents}
                  placeholder="Например: 5000 для $50.00"
                  value={payoutForm.amount_cents}
                  onChange={(e) => setPayoutForm(prev => ({ ...prev, amount_cents: e.target.value }))}
                />
                {payoutForm.amount_cents && !isNaN(parseInt(payoutForm.amount_cents)) && (
                  <p className="text-sm text-muted-foreground">
                    = {formatCents(parseInt(payoutForm.amount_cents), 'USD')}
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
