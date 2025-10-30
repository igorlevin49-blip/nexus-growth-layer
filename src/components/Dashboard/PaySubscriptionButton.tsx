import { useState } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Loader2, CreditCard, FileText } from "lucide-react";
import { useManualPayment } from "@/hooks/useManualPayment";
import { Alert, AlertDescription } from "@/components/ui/alert";

export function PaySubscriptionButton() {
  const [isProcessing, setIsProcessing] = useState(false);
  const [showManualOption, setShowManualOption] = useState(false);
  const { createManualSubscription } = useManualPayment();

  const handlePayment = async () => {
    setIsProcessing(true);

    try {
      const { data, error } = await supabase.functions.invoke(
        'freedompay-create-subscription-payment',
        {
          headers: {
            Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token}`,
          },
        }
      );

      if (error) {
        console.error('Edge function error:', error);
        
        // Check if provider not configured (422 status)
        if (error.message?.includes('PROVIDER_NOT_CONFIGURED') || error.message?.includes('422')) {
          setShowManualOption(true);
          toast.error('Онлайн-оплата временно недоступна', {
            description: 'Вы можете отправить заявку на ручную оплату'
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
    <div className="space-y-2 w-full">
      {showManualOption && (
        <Alert>
          <FileText className="h-4 w-4" />
          <AlertDescription>
            Онлайн-оплата временно недоступна. Вы можете отправить заявку на ручную оплату.
          </AlertDescription>
        </Alert>
      )}
      <div className="flex gap-2 w-full">
        <Button 
          onClick={handlePayment} 
          disabled={isProcessing || createManualSubscription.isPending} 
          className="flex-1"
        >
          {isProcessing ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Создание...
            </>
          ) : (
            <>
              <CreditCard className="mr-2 h-4 w-4" />
              Оплатить онлайн
            </>
          )}
        </Button>
        <Button 
          onClick={handleManualPayment}
          disabled={isProcessing || createManualSubscription.isPending}
          variant="outline"
          className="flex-1"
        >
          {createManualSubscription.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Отправка...
            </>
          ) : (
            <>
              <FileText className="mr-2 h-4 w-4" />
              Оплатить вручную
            </>
          )}
        </Button>
      </div>
    </div>
  );
}
