import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

interface RecalculateResult {
  success: boolean;
  subscriptions_processed: number;
  commissions_created: number;
  commissions_skipped: number;
  total_kzt?: number;
  dry_run?: boolean;
}

interface RecalculateOptions {
  dryRun?: boolean;
  sponsorId?: string;
}

/**
 * Hook to backfill missing S1 subscription commissions
 * Uses the backfill_missing_s1_commissions function
 * 
 * Сигнатура функции в БД:
 * backfill_missing_s1_commissions(p_admin_id uuid, p_dry_run boolean DEFAULT true, p_sponsor_id uuid DEFAULT NULL)
 */
export function useRecalculateS1Commissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (options: RecalculateOptions = {}) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { dryRun = false, sponsorId = null } = options;

      // Используем правильные параметры согласно сигнатуре функции в БД
      const { data, error } = await supabase.rpc('backfill_missing_s1_commissions', {
        p_admin_id: user.id,
        p_dry_run: dryRun,
        p_sponsor_id: sponsorId
      });

      if (error) throw error;
      return data as unknown as RecalculateResult;
    },
    onSuccess: (data, variables) => {
      // Инвалидируем кеши только если это был реальный backfill (не dry run)
      if (!variables?.dryRun) {
        queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['balance'] });
        queryClient.invalidateQueries({ queryKey: ['sponsors-with-missing-commissions'] });
        queryClient.invalidateQueries({ queryKey: ['admin-commission-audit'] });
        
        toast.success('Комиссии пересчитаны', {
          description: `Обработано подписок: ${data.subscriptions_processed}, создано комиссий: ${data.commissions_created}, пропущено: ${data.commissions_skipped}`
        });
      }
    },
    onError: (error: Error) => {
      console.error('Error recalculating commissions:', error);
      toast.error('Ошибка пересчета комиссий', {
        description: error.message
      });
    }
  });
}

/**
 * Hook to recalculate commissions for a specific user
 * Uses backfill_missing_multilevel_commissions with target_user_id
 */
export function useRecalculateUserCommissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ userId, dryRun = false }: { userId: string; dryRun?: boolean }) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('backfill_missing_multilevel_commissions', {
        p_admin_id: user.id,
        p_dry_run: dryRun,
        p_target_user_id: userId
      });

      if (error) throw error;
      return data as unknown as RecalculateResult;
    },
    onSuccess: (data, variables) => {
      if (!variables?.dryRun) {
        queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['balance'] });
        queryClient.invalidateQueries({ queryKey: ['admin-commission-audit', variables.userId] });
        
        toast.success('Комиссии пользователя пересчитаны', {
          description: `Создано комиссий: ${data.commissions_created}, пропущено: ${data.commissions_skipped}`
        });
      }
    },
    onError: (error: Error) => {
      console.error('Error recalculating user commissions:', error);
      toast.error('Ошибка пересчета комиссий пользователя', {
        description: error.message
      });
    }
  });
}
