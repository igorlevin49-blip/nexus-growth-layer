import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Wallet, Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import { formatKZT } from "@/utils/formatMoney";

interface PayFromBalanceButtonProps {
  requiredAmountKzt: number;
  availableBalanceKzt: number;
  onSuccess?: () => void;
}

export function PayFromBalanceButton({ 
  requiredAmountKzt, 
  availableBalanceKzt,
  onSuccess 
}: PayFromBalanceButtonProps) {
  const [isLoading, setIsLoading] = useState(false);
  const queryClient = useQueryClient();
  
  const canPay = availableBalanceKzt >= requiredAmountKzt;
  
  const handlePayFromBalance = async () => {
    if (!canPay) {
      toast.error("Недостаточно средств на балансе");
      return;
    }
    
    setIsLoading(true);
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        toast.error("Необходима авторизация");
        return;
      }
      
      // @ts-ignore - function exists but not in generated types yet
      const { data, error } = await supabase.rpc("pay_activation_from_balance", {
        p_user_id: user.id
      }) as { data: { success: boolean; error?: string; order_id?: string } | null; error: Error | null };
      
      if (error) throw error;
      
      const result = data as { success: boolean; error?: string; order_id?: string };
      
      if (result?.success) {
        toast.success("Активация оплачена с баланса!", {
          description: `Списано ${formatKZT(requiredAmountKzt, "KZT")}`
        });
        
        // Invalidate relevant queries
        queryClient.invalidateQueries({ queryKey: ["balance"] });
        queryClient.invalidateQueries({ queryKey: ["profile"] });
        queryClient.invalidateQueries({ queryKey: ["transactions"] });
        
        onSuccess?.();
      } else {
        const errorMessage = result?.error === "insufficient_balance" 
          ? "Недостаточно средств на балансе"
          : result?.error || "Ошибка при оплате";
        toast.error(errorMessage);
      }
    } catch (error) {
      console.error("Pay from balance error:", error);
      toast.error("Ошибка при оплате с баланса");
    } finally {
      setIsLoading(false);
    }
  };
  
  return (
    <Button
      onClick={handlePayFromBalance}
      disabled={!canPay || isLoading}
      variant={canPay ? "default" : "outline"}
      className="w-full"
    >
      {isLoading ? (
        <>
          <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          Обработка...
        </>
      ) : (
        <>
          <Wallet className="h-4 w-4 mr-2" />
          {canPay 
            ? `Оплатить с баланса (${formatKZT(requiredAmountKzt, "KZT")})`
            : `Недостаточно средств (нужно ${formatKZT(requiredAmountKzt, "KZT")})`
          }
        </>
      )}
    </Button>
  );
}
