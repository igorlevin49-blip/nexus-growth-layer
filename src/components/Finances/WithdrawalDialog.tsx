import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useWithdrawals } from "@/hooks/useWithdrawals";
import { usePaymentMethods } from "@/hooks/usePaymentMethods";
import { useBalance } from "@/hooks/useBalance";
import { formatCents, parseCentsInput } from "@/utils/formatMoney";

interface WithdrawalDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function WithdrawalDialog({ open, onOpenChange }: WithdrawalDialogProps) {
  const [amount, setAmount] = useState("");
  const [selectedMethod, setSelectedMethod] = useState("");
  
  const { data: balance } = useBalance();
  const { data: methods } = usePaymentMethods();
  const { createWithdrawal } = useWithdrawals();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!selectedMethod || !amount) return;
    
    const amountCents = parseCentsInput(amount);
    
    if (balance && amountCents > balance.available_cents) {
      return;
    }

    await createWithdrawal.mutateAsync({
      amount_cents: amountCents,
      method_id: selectedMethod
    });

    setAmount("");
    setSelectedMethod("");
    onOpenChange(false);
  };

  const defaultMethod = methods?.find(m => m.is_default);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Вывести средства</DialogTitle>
          <DialogDescription>
            Доступно для вывода: {balance ? formatCents(balance.available_cents) : "$0.00"}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="amount">Сумма</Label>
            <Input
              id="amount"
              type="text"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="method">Способ оплаты</Label>
            <Select value={selectedMethod} onValueChange={setSelectedMethod} required>
              <SelectTrigger id="method">
                <SelectValue placeholder="Выберите способ" />
              </SelectTrigger>
              <SelectContent>
                {methods && methods.length > 0 ? (
                  methods.map((method) => (
                    <SelectItem key={method.id} value={method.id}>
                      {method.masked} {method.is_default && "(по умолчанию)"}
                    </SelectItem>
                  ))
                ) : (
                  <SelectItem value="none" disabled>
                    Нет доступных способов
                  </SelectItem>
                )}
              </SelectContent>
            </Select>
          </div>

          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} className="flex-1">
              Отмена
            </Button>
            <Button 
              type="submit" 
              className="flex-1 hero-gradient border-0"
              disabled={!amount || !selectedMethod || createWithdrawal.isPending}
            >
              {createWithdrawal.isPending ? "Обработка..." : "Вывести"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
