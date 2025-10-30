import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Loader2, CreditCard, FileText } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { useManualPayment } from "@/hooks/useManualPayment";
import { Alert, AlertDescription } from "@/components/ui/alert";

export interface PayActivationButtonProps {
  requiredAmountUSD: number;
  currentAmountUSD: number;
}

export function PayActivationButton({ 
  requiredAmountUSD, 
  currentAmountUSD 
}: PayActivationButtonProps) {
  const { user } = useAuth();
  const [isProcessing, setIsProcessing] = useState(false);
  const [activationProducts, setActivationProducts] = useState<any[]>([]);
  const [showManualOption, setShowManualOption] = useState(false);
  const { createManualActivation } = useManualPayment();

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

  const handlePayment = async () => {
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
          body: { product_id: product.id },
          headers: {
            Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token}`,
          },
        }
      );

      if (error) {
        if (error.message?.includes('SUBSCRIPTION_REQUIRED')) {
          toast.error('Сначала активируйте годовую подписку');
        } else if (error.message?.includes('PROVIDER_NOT_CONFIGURED')) {
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
          disabled={isProcessing || createManualActivation.isPending} 
          className="flex-1"
        >
          {isProcessing ? (
            <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Создание...</>
          ) : (
            <><CreditCard className="mr-2 h-4 w-4" />Оплатить онлайн</>
          )}
        </Button>
        <Button 
          onClick={handleManualPayment}
          disabled={isProcessing || createManualActivation.isPending}
          variant="outline"
          className="flex-1"
        >
          {createManualActivation.isPending ? (
            <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Отправка...</>
          ) : (
            <><FileText className="mr-2 h-4 w-4" />Оплатить вручную</>
          )}
        </Button>
      </div>
    </div>
  );
}
