import { useMutation, useQueryClient } from "@tanstack/react-query";
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
 * Hook to backfill missing S1 subscription commissions
 * Uses the backfill_missing_s1_commissions function
 */
export function useRecalculateS1Commissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (daysBack: number = 30) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('backfill_missing_s1_commissions', {
        p_admin_id: user.id,
        p_days_back: daysBack
      });

      if (error) throw error;
      return data as unknown as RecalculateResult;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      queryClient.invalidateQueries({ queryKey: ['balance'] });
      
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
