import { useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

interface RecalculateResult {
  success: boolean;
  subscriptions_processed: number;
  commissions_created: number;
  commissions_skipped: number;
}

/**
 * Hook to recalculate all S1 subscription commissions
 * This will create missing commission records for all 5 levels
 */
export function useRecalculateS1Commissions() {
  const { user } = useAuth();

  return useMutation({
    mutationFn: async () => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('recalculate_all_s1_commissions', {
        p_admin_id: user.id
      });

      if (error) throw error;
      return data as unknown as RecalculateResult;
    },
    onSuccess: (data) => {
      toast.success('Комиссии пересчитаны', {
        description: `Обработано подписок: ${data.subscriptions_processed}, создано комиссий: ${data.commissions_created}, пропущено: ${data.commissions_skipped}`
      });
    },
    onError: (error: any) => {
      console.error('Error recalculating commissions:', error);
      toast.error('Ошибка пересчета комиссий', {
        description: error.message
      });
    }
  });
}
