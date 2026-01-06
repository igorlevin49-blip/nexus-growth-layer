import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { CreditCard, Smartphone, Banknote, Loader2 } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";

interface PaymentMethodDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelectMethod: (method: "card" | "kaspi" | "cash") => void;
  isProcessing: boolean;
  providerNotConfigured: boolean;
  requiresSubscription?: boolean;
  type: "subscription" | "activation";
  amount?: { kzt: number };
}

export function PaymentMethodDialog({
  open,
  onOpenChange,
  onSelectMethod,
  isProcessing,
  providerNotConfigured,
  requiresSubscription = false,
  type,
  amount,
}: PaymentMethodDialogProps) {
  const title = type === "subscription" ? "Оплата подписки" : "Оплата активации";
  const description = type === "subscription" 
    ? "Подписка открывает доступ к реферальной программе" 
    : "Для получения MLM-бонусов необходима месячная активация";

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>

        {amount && (
          <div className="py-4 text-center border-y">
            <div className="text-2xl font-bold">{amount.kzt.toLocaleString()} ₸</div>
          </div>
        )}

        {requiresSubscription && (
          <Alert variant="destructive">
            <AlertDescription>
              Сначала активируйте годовую подписку
            </AlertDescription>
          </Alert>
        )}

        {providerNotConfigured && (
          <Alert>
            <AlertDescription>
              Онлайн-оплата временно недоступна — можно выбрать «Наличные»
            </AlertDescription>
          </Alert>
        )}

        <div className="grid gap-3 py-4">
          <Button
            onClick={() => onSelectMethod("card")}
            disabled={isProcessing || requiresSubscription || providerNotConfigured}
            variant="outline"
            className="justify-start h-auto py-4"
          >
            {isProcessing ? (
              <Loader2 className="mr-3 h-5 w-5 animate-spin" />
            ) : (
              <CreditCard className="mr-3 h-5 w-5" />
            )}
            <div className="text-left">
              <div className="font-semibold">Банковская карта</div>
              <div className="text-xs text-muted-foreground">Оплата через FreedomPay</div>
            </div>
          </Button>

          <Button
            onClick={() => onSelectMethod("kaspi")}
            disabled={isProcessing || requiresSubscription || providerNotConfigured}
            variant="outline"
            className="justify-start h-auto py-4"
          >
            {isProcessing ? (
              <Loader2 className="mr-3 h-5 w-5 animate-spin" />
            ) : (
              <Smartphone className="mr-3 h-5 w-5" />
            )}
            <div className="text-left">
              <div className="font-semibold">Kaspi</div>
              <div className="text-xs text-muted-foreground">Оплата через Kaspi QR</div>
            </div>
          </Button>

          <Button
            onClick={() => onSelectMethod("cash")}
            disabled={isProcessing || requiresSubscription}
            variant="outline"
            className="justify-start h-auto py-4"
          >
            {isProcessing ? (
              <Loader2 className="mr-3 h-5 w-5 animate-spin" />
            ) : (
              <Banknote className="mr-3 h-5 w-5" />
            )}
            <div className="text-left">
              <div className="font-semibold">Наличные</div>
              <div className="text-xs text-muted-foreground">Ручная оплата через администратора</div>
            </div>
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
