import { useState } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Loader2, CreditCard } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";

export function PaySubscriptionButton() {
  const { user } = useAuth();
  const [isProcessing, setIsProcessing] = useState(false);

  const handlePayment = async () => {
    if (!user) {
      toast.error("Требуется авторизация");
      return;
    }

    setIsProcessing(true);

    try {
      console.log('[PAY_SUBSCRIPTION] Starting payment process');

      // Call subscription payment edge function
      const { data, error } = await supabase.functions.invoke(
        'freedompay-create-subscription-payment',
        {
          headers: {
            Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token}`,
          },
        }
      );

      if (error) {
        console.error('[PAY_SUBSCRIPTION] Error:', error);
        
        // Handle specific error types
        if (error.message?.includes('UNAUTHORIZED')) {
          toast.error('Требуется авторизация. Пожалуйста, войдите в систему');
        } else if (error.message?.includes('CONFIGURATION_ERROR')) {
          toast.error('Настройки платёжной системы не завершены. Обратитесь к администратору');
        } else {
          toast.error(`Ошибка создания платежа: ${error.message}`);
        }
        return;
      }

      if (!data?.payment_url) {
        console.error('[PAY_SUBSCRIPTION] No payment URL in response:', data);
        toast.error('Не удалось получить ссылку на оплату');
        return;
      }

      console.log('[PAY_SUBSCRIPTION] Payment URL received:', data.payment_url);
      
      // Show success message with details
      toast.success(`Подписка: $${data.amount_usd} (${data.amount_kzt} ₸)`);
      
      // Redirect to payment page
      window.location.href = data.payment_url;

    } catch (error: any) {
      console.error('[PAY_SUBSCRIPTION] Unexpected error:', error);
      
      // Parse error response
      if (error.context?.body) {
        try {
          const errorData = JSON.parse(error.context.body);
          toast.error(errorData.message || 'Неизвестная ошибка', {
            description: errorData.correlationId ? `Код: ${errorData.correlationId}` : undefined
          });
        } catch {
          toast.error('Ошибка при создании платежа');
        }
      } else {
        toast.error(error.message || 'Неизвестная ошибка при создании платежа');
      }
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <Button
      onClick={handlePayment}
      disabled={isProcessing}
      className="w-full"
      size="lg"
    >
      {isProcessing ? (
        <>
          <Loader2 className="mr-2 h-5 w-5 animate-spin" />
          Создание платежа...
        </>
      ) : (
        <>
          <CreditCard className="mr-2 h-5 w-5" />
          Оплатить подписку
        </>
      )}
    </Button>
  );
}
