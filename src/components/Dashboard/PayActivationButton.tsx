import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { CreditCard } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { useManualPayment } from "@/hooks/useManualPayment";
import { PaymentMethodDialog } from "./PaymentMethodDialog";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

export interface PayActivationButtonProps {
  requiredAmountKZT: number;
  currentAmountKZT: number;
  activationDueFrom: Date | null;
  isActivationRequired: boolean;
}

export function PayActivationButton({ 
  requiredAmountKZT, 
  currentAmountKZT,
  activationDueFrom,
  isActivationRequired
}: PayActivationButtonProps) {
  const { user } = useAuth();
  const { createManualActivation } = useManualPayment();
  const [isProcessing, setIsProcessing] = useState(false);
  const [activationProducts, setActivationProducts] = useState<any[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [providerNotConfigured, setProviderNotConfigured] = useState(false);
  const [amount, setAmount] = useState<{ kzt: number } | undefined>();

  useEffect(() => {
    const fetchProducts = async () => {
      const { data } = await supabase
        .from('products')
        .select('*')
        .eq('is_activation', true)
        .order('price_usd', { ascending: true });
      
      if (data && data.length > 0) {
        setActivationProducts(data);
      }
    };
    fetchProducts();
  }, []);

  const handleOpenDialog = async () => {
    // Use KZT directly - no conversion needed
    setAmount({ kzt: requiredAmountKZT });
    setDialogOpen(true);
  };

  const handleSelectMethod = async (method: "card" | "kaspi" | "cash") => {
    setIsProcessing(true);
    setDialogOpen(false);

    if (method === "cash") {
      await handleManualPayment();
      return;
    }

    await handlePayment(method);
  };

  const handlePayment = async (method: "card" | "kaspi") => {
    if (!user) {
      toast.error("Требуется авторизация");
      return;
    }

    if (activationProducts.length === 0) {
      toast.error("Активационные товары не найдены");
      return;
    }

    const product = activationProducts[0];
    setIsProcessing(true);

    try {
      const { data, error } = await supabase.functions.invoke(
        'freedompay-create-payment',
        {
          body: {
            method,
            products: activationProducts.map(p => ({
              product_id: p.id,
              quantity: 1,
              price_usd: p.price_usd
            }))
          },
          headers: {
            Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token}`,
          },
        }
      );

      if (error) {
        console.error('Edge function error:', error);
        
        if (error.message?.includes('PROVIDER_NOT_CONFIGURED') || error.message?.includes('422')) {
          setProviderNotConfigured(true);
          setDialogOpen(true);
          toast.error('Онлайн-оплата временно недоступна', {
            description: 'Выберите способ «Наличные»'
          });
        } else if (error.message?.includes('NO_ACTIVE_SUBSCRIPTION')) {
          toast.error('Сначала активируйте подписку');
        } else {
          toast.error(`Ошибка: ${error.message}`);
        }
        return;
      }

      if (data?.payment_url) {
        toast.success(`${data.product_title}: $${data.amount_usd}`);
        window.location.href = data.payment_url;
      }
    } catch (error: any) {
      toast.error(error.message || 'Ошибка при создании платежа');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleManualPayment = async () => {
    if (activationProducts.length === 0) {
      toast.error("Активационные товары не найдены");
      return;
    }

    const product = activationProducts[0];
    await createManualActivation.mutateAsync({ product_id: product.id });
  };

  const isDisabled = 
    isProcessing || 
    createManualActivation.isPending || 
    currentAmountKZT >= requiredAmountKZT ||
    !isActivationRequired;

  const getTooltipText = () => {
    if (!isActivationRequired && activationDueFrom) {
      return `Первая месячная активация требуется с ${format(activationDueFrom, "dd.MM.yyyy", { locale: ru })}. Сейчас ничего делать не нужно.`;
    }
    if (currentAmountKZT >= requiredAmountKZT) {
      return "Активация уже выполнена";
    }
    return "Оплатить активацию";
  };

  return (
    <>
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <div className="w-full">
              <Button 
                onClick={handleOpenDialog} 
                disabled={isDisabled} 
                className="w-full"
              >
                <CreditCard className="mr-2 h-4 w-4" />
                Оплатить
              </Button>
            </div>
          </TooltipTrigger>
          {isDisabled && (
            <TooltipContent>
              <p>{getTooltipText()}</p>
            </TooltipContent>
          )}
        </Tooltip>
      </TooltipProvider>

      <PaymentMethodDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        onSelectMethod={handleSelectMethod}
        isProcessing={isProcessing || createManualActivation.isPending}
        providerNotConfigured={providerNotConfigured}
        type="activation"
        amount={amount}
      />
    </>
  );
}
