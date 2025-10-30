import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Loader2, CreditCard } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";

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

  return (
    <Button onClick={handlePayment} disabled={isProcessing} className="w-full">
      {isProcessing ? (
        <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Создание...</>
      ) : (
        <><CreditCard className="mr-2 h-4 w-4" />Оплатить активацию</>
      )}
    </Button>
  );
}
