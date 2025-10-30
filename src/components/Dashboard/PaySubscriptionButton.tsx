import { useState } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { CreditCard } from "lucide-react";
import { useManualPayment } from "@/hooks/useManualPayment";
import { PaymentMethodDialog } from "./PaymentMethodDialog";

export function PaySubscriptionButton() {
  const [isProcessing, setIsProcessing] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [providerNotConfigured, setProviderNotConfigured] = useState(false);
  const [amount, setAmount] = useState<{ usd: number; kzt: number } | undefined>();
  const { createManualSubscription } = useManualPayment();

  const handleOpenDialog = async () => {
    // Fetch amount
    try {
      const { data: settings } = await supabase
        .from('mlm_settings')
        .select('value')
        .eq('key', 'subscription_price_usd')
        .single();

      const priceUSD = typeof settings?.value === 'number' ? settings.value : 100;
      
      const { data: shopSettings } = await supabase
        .from('shop_settings')
        .select('rate_usd_kzt')
        .eq('id', 1)
        .single();

      const rate = typeof shopSettings?.rate_usd_kzt === 'number' ? shopSettings.rate_usd_kzt : 450;
      const priceKZT = Math.round(priceUSD * rate);

      setAmount({ usd: priceUSD, kzt: priceKZT });
      setDialogOpen(true);
    } catch (error) {
      console.error('Error fetching amount:', error);
      setDialogOpen(true);
    }
  };

  const handleSelectMethod = async (method: "card" | "kaspi" | "cash") => {
    setIsProcessing(true);
    setDialogOpen(false);

    if (method === "cash") {
      await handleManualPayment();
      return;
    }

    try {
      const { data, error } = await supabase.functions.invoke(
        'freedompay-create-subscription-payment',
        {
          body: { method },
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
        } else {
          toast.error(`Ошибка: ${error.message}`);
        }
        return;
      }

      if (data?.payment_url) {
        toast.success(`Подписка: $${data.amount_usd}`);
        window.location.href = data.payment_url;
      }
    } catch (error: any) {
      console.error('Payment error:', error);
      toast.error(error.message || 'Ошибка при создании платежа');
    } finally {
      setIsProcessing(false);
    }
  };

  const handleManualPayment = async () => {
    setIsProcessing(true);
    try {
      // Get subscription price from settings
      const { data: settings } = await supabase
        .from('mlm_settings')
        .select('value')
        .eq('key', 'subscription_price_usd')
        .single();

      const priceUSD = typeof settings?.value === 'number' ? settings.value : 100;
      
      // Get exchange rate
      const { data: shopSettings } = await supabase
        .from('shop_settings')
        .select('rate_usd_kzt')
        .eq('id', 1)
        .single();

      const rate = typeof shopSettings?.rate_usd_kzt === 'number' ? shopSettings.rate_usd_kzt : 450;
      const priceKZT = Math.round(priceUSD * rate);

      await createManualSubscription.mutateAsync({
        amount_usd: priceUSD,
        amount_kzt: priceKZT
      });
    } catch (error) {
      console.error('Manual payment error:', error);
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <>
      <Button 
        onClick={handleOpenDialog} 
        disabled={isProcessing || createManualSubscription.isPending} 
        className="w-full"
      >
        <CreditCard className="mr-2 h-4 w-4" />
        Оплатить
      </Button>

      <PaymentMethodDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        onSelectMethod={handleSelectMethod}
        isProcessing={isProcessing || createManualSubscription.isPending}
        providerNotConfigured={providerNotConfigured}
        type="subscription"
        amount={amount}
      />
    </>
  );
}
