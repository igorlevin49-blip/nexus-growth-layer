import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useWithdrawals } from "@/hooks/useWithdrawals";
import { usePaymentMethods } from "@/hooks/usePaymentMethods";
import { useBalance } from "@/hooks/useBalance";
import { formatKZT, parseKZTInput } from "@/utils/formatMoney";
import { toast } from "sonner";
import { AlertCircle } from "lucide-react";

interface WithdrawalDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const MIN_WITHDRAWAL_KZT = 50000; // 500 тенге

export function WithdrawalDialog({ open, onOpenChange }: WithdrawalDialogProps) {
  const [amount, setAmount] = useState("");
  const [selectedMethod, setSelectedMethod] = useState("");
  
  const { data: balance } = useBalance();
  const { data: methods } = usePaymentMethods();
  const { data: withdrawals, createWithdrawal } = useWithdrawals();

  // Защита от отрицательного баланса - показываем 0
  const availableBalance = Math.max(0, balance?.available_kzt || 0);
  const hasNegativeBalance = (balance?.available_kzt || 0) < 0;
  
  // Проверяем есть ли уже processing вывод
  const hasProcessingWithdrawal = withdrawals?.some(w => w.status === 'processing');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!selectedMethod || !amount) return;
    
    const amountKzt = parseKZTInput(amount);
    
    // Проверка минимальной суммы
    if (amountKzt < MIN_WITHDRAWAL_KZT) {
      toast.error(`Минимальная сумма вывода: ${formatKZT(MIN_WITHDRAWAL_KZT)}`);
      return;
    }
    
    // Проверка доступного баланса
    if (amountKzt > availableBalance) {
      toast.error(`Недостаточно средств. Доступно: ${formatKZT(availableBalance)}`);
      return;
    }

    try {
      await createWithdrawal.mutateAsync({
        amount_kzt: amountKzt,
        method_id: selectedMethod
      });

      setAmount("");
      setSelectedMethod("");
      onOpenChange(false);
    } catch (error) {
      // Ошибка уже обрабатывается в хуке
    }
  };

  const defaultMethod = methods?.find(m => m.is_default);
  const canWithdraw = availableBalance >= MIN_WITHDRAWAL_KZT && !hasNegativeBalance && !hasProcessingWithdrawal;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Вывести средства</DialogTitle>
          <DialogDescription>
            Доступно для вывода: {formatKZT(availableBalance)}
          </DialogDescription>
        </DialogHeader>

        {hasNegativeBalance && (
          <div className="flex items-center gap-2 p-3 bg-destructive/10 text-destructive rounded-md text-sm">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>Баланс временно недоступен. Обратитесь в поддержку.</span>
          </div>
        )}

        {hasProcessingWithdrawal && (
          <div className="flex items-center gap-2 p-3 bg-yellow-500/10 text-yellow-700 dark:text-yellow-400 rounded-md text-sm">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>У вас уже есть заявка на вывод в обработке. Дождитесь её завершения.</span>
          </div>
        )}

        {!canWithdraw && !hasNegativeBalance && !hasProcessingWithdrawal && (
          <div className="flex items-center gap-2 p-3 bg-muted text-muted-foreground rounded-md text-sm">
            <AlertCircle className="h-4 w-4 shrink-0" />
            <span>Минимальная сумма для вывода: {formatKZT(MIN_WITHDRAWAL_KZT)}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="amount">Сумма</Label>
            <Input
              id="amount"
              type="text"
              placeholder="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              required
              disabled={!canWithdraw}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="method">Способ оплаты</Label>
            <Select value={selectedMethod} onValueChange={setSelectedMethod} required disabled={!canWithdraw}>
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
              disabled={!amount || !selectedMethod || createWithdrawal.isPending || !canWithdraw}
            >
              {createWithdrawal.isPending ? "Обработка..." : "Вывести"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
