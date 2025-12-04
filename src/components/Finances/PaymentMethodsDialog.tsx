import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { usePaymentMethods } from "@/hooks/usePaymentMethods";
import { Trash2, Star } from "lucide-react";

interface PaymentMethodsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function PaymentMethodsDialog({ open, onOpenChange }: PaymentMethodsDialogProps) {
  const [showAdd, setShowAdd] = useState(false);
  const [type, setType] = useState<string>('card');
  const [masked, setMasked] = useState("");
  
  const { data: methods, addMethod, removeMethod, setDefault } = usePaymentMethods();

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!masked) return;

    await addMethod.mutateAsync({
      type: type as any,
      masked,
      meta: {},
      is_default: !methods || methods.length === 0
    });

    setMasked("");
    setShowAdd(false);
  };

  const typeLabels: Record<string, string> = {
    card: 'Карта',
    bank: 'Банк',
    crypto: 'Крипто',
    cash: 'Наличные в кассе',
    other: 'Другое'
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Способы оплаты</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {methods && methods.length > 0 ? (
            <div className="space-y-2">
              {methods.map((method) => (
                <div key={method.id} className="flex items-center justify-between p-3 border border-border rounded-lg">
                  <div className="flex items-center space-x-3">
                    <div>
                      <p className="font-medium">{method.masked}</p>
                      <p className="text-sm text-muted-foreground">{typeLabels[method.type]}</p>
                    </div>
                    {method.is_default && (
                      <Badge variant="outline" className="text-xs">
                        По умолчанию
                      </Badge>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {!method.is_default && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setDefault.mutate(method.id)}
                      >
                        <Star className="h-4 w-4" />
                      </Button>
                    )}
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => removeMethod.mutate(method.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-center text-muted-foreground py-4">
              Нет добавленных способов оплаты
            </p>
          )}

          {!showAdd ? (
            <Button onClick={() => setShowAdd(true)} variant="outline" className="w-full">
              Добавить способ оплаты
            </Button>
          ) : (
            <form onSubmit={handleAdd} className="space-y-4 border-t pt-4">
              <div className="space-y-2">
                <Label htmlFor="type">Тип</Label>
                <Select value={type} onValueChange={(v) => setType(v as any)} required>
                  <SelectTrigger id="type">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="card">Карта</SelectItem>
                    <SelectItem value="bank">Банк</SelectItem>
                    <SelectItem value="crypto">Крипто</SelectItem>
                    <SelectItem value="cash">Наличные в кассе</SelectItem>
                    <SelectItem value="other">Другое</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="masked">Номер/Реквизиты</Label>
                <Input
                  id="masked"
                  type="text"
                  placeholder="****1234"
                  value={masked}
                  onChange={(e) => setMasked(e.target.value)}
                  required
                />
              </div>

              <div className="flex gap-2">
                <Button type="button" variant="outline" onClick={() => setShowAdd(false)} className="flex-1">
                  Отмена
                </Button>
                <Button type="submit" className="flex-1" disabled={addMethod.isPending}>
                  {addMethod.isPending ? "Добавление..." : "Добавить"}
                </Button>
              </div>
            </form>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
