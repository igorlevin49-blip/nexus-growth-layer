import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { useAutoWithdraw } from "@/hooks/useAutoWithdraw";
import { usePaymentMethods } from "@/hooks/usePaymentMethods";
import { formatCents, parseCentsInput } from "@/utils/formatMoney";

interface AutoWithdrawDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function AutoWithdrawDialog({ open, onOpenChange }: AutoWithdrawDialogProps) {
  const [enabled, setEnabled] = useState(false);
  const [threshold, setThreshold] = useState("");
  const [minAmount, setMinAmount] = useState("");
  const [schedule, setSchedule] = useState<'daily' | 'weekly' | 'monthly'>('weekly');
  const [methodId, setMethodId] = useState("");

  const { data: rule, updateRule } = useAutoWithdraw();
  const { data: methods } = usePaymentMethods();

  useEffect(() => {
    if (rule) {
      setEnabled(rule.enabled);
      setThreshold((rule.threshold_cents / 100).toString());
      setMinAmount((rule.min_amount_cents / 100).toString());
      setSchedule(rule.schedule);
      setMethodId(rule.method_id || "");
    }
  }, [rule]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    await updateRule.mutateAsync({
      enabled,
      threshold_cents: parseCentsInput(threshold),
      min_amount_cents: parseCentsInput(minAmount),
      schedule,
      method_id: methodId || null
    });

    onOpenChange(false);
  };

  const scheduleLabels: Record<string, string> = {
    daily: 'Ежедневно',
    weekly: 'Еженедельно',
    monthly: 'Ежемесячно'
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Настройки автовывода</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-center justify-between">
            <Label htmlFor="enabled">Включить автовывод</Label>
            <Switch
              id="enabled"
              checked={enabled}
              onCheckedChange={setEnabled}
            />
          </div>

          {enabled && (
            <>
              <div className="space-y-2">
                <Label htmlFor="threshold">Порог автовывода ($)</Label>
                <Input
                  id="threshold"
                  type="text"
                  placeholder="100.00"
                  value={threshold}
                  onChange={(e) => setThreshold(e.target.value)}
                  required
                />
                <p className="text-xs text-muted-foreground">
                  Вывод будет происходить при достижении этой суммы
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="minAmount">Минимальная сумма ($)</Label>
                <Input
                  id="minAmount"
                  type="text"
                  placeholder="50.00"
                  value={minAmount}
                  onChange={(e) => setMinAmount(e.target.value)}
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="schedule">Расписание</Label>
                <Select value={schedule} onValueChange={(v) => setSchedule(v as any)} required>
                  <SelectTrigger id="schedule">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="daily">Ежедневно</SelectItem>
                    <SelectItem value="weekly">Еженедельно</SelectItem>
                    <SelectItem value="monthly">Ежемесячно</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="method">Способ оплаты</Label>
                <Select value={methodId} onValueChange={setMethodId} required>
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
            </>
          )}

          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)} className="flex-1">
              Отмена
            </Button>
            <Button 
              type="submit" 
              className="flex-1"
              disabled={updateRule.isPending}
            >
              {updateRule.isPending ? "Сохранение..." : "Сохранить"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
