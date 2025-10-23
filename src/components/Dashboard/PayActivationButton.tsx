import { useState } from "react";
import { Button } from "@/components/ui/button";
import { CreditCard } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface PayActivationButtonProps {
  requiredAmountCents: number;
  currentAmountCents: number;
}

export const PayActivationButton = ({ 
  requiredAmountCents, 
  currentAmountCents 
}: PayActivationButtonProps) => {
  const [isProcessing, setIsProcessing] = useState(false);

  const handlePayment = async () => {
    try {
      setIsProcessing(true);

      const remainingAmount = requiredAmountCents - currentAmountCents;
      const amountToPay = remainingAmount > 0 ? remainingAmount : requiredAmountCents;

      const { data, error } = await supabase.functions.invoke('freedompay-create-payment', {
        body: {
          amount_cents: amountToPay,
          description: 'Оплата месячной активации',
        },
      });

      if (error) {
        throw error;
      }

      if (data?.payment_url) {
        // Redirect to payment page
        window.location.href = data.payment_url;
      } else {
        throw new Error('Payment URL not received');
      }

    } catch (error) {
      console.error('Payment error:', error);
      toast.error('Ошибка при создании платежа', {
        description: error.message || 'Попробуйте позже',
      });
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
      <CreditCard className="mr-2 h-4 w-4" />
      {isProcessing ? 'Обработка...' : 'Оплатить активацию'}
    </Button>
  );
};