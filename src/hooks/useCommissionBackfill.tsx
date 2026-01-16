import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

interface SponsorWithMissing {
  sponsor_id: string;
  sponsor_name: string;
  sponsor_email: string;
  missing_count: number;
  missing_amount_kzt: number;  // Суммы уже в целых тенге, не в центах
  partners_count: number;
}

interface BackfillResult {
  success: boolean;
  subscriptions_processed: number;
  commissions_created: number;
  commissions_skipped: number;
  total_kzt: number;  // Сумма в целых тенге
  dry_run: boolean;
  details?: Array<{
    subscription_id: string;
    subscriber_name: string;
    amount_kzt: number;
    commission_kzt: number;  // Комиссия в целых тенге
  }>;
}

/**
 * Hook to get list of sponsors with missing commissions
 */
export function useSponsorsWithMissingCommissions() {
  const { user } = useAuth();

  return useQuery({
    queryKey: ['sponsors-with-missing-commissions'],
    queryFn: async () => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('get_sponsors_with_missing_commissions', {
        p_admin_id: user.id
      });

      if (error) throw error;
      return (data || []) as SponsorWithMissing[];
    },
    enabled: !!user?.id
  });
}

/**
 * Hook to backfill missing commissions for a specific sponsor
 */
export function useBackfillSponsorCommissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ sponsorId, dryRun = true }: { sponsorId: string; dryRun?: boolean }) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('backfill_sponsor_commissions', {
        p_admin_id: user.id,
        p_sponsor_id: sponsorId,
        p_dry_run: dryRun
      });

      if (error) throw error;
      return data as unknown as BackfillResult;
    },
    onSuccess: (data, variables) => {
      if (!variables.dryRun) {
        queryClient.invalidateQueries({ queryKey: ['sponsors-with-missing-commissions'] });
        queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['balance'] });
        
        toast.success('Комиссии доначислены', {
          description: `Создано комиссий: ${data.commissions_created}, сумма: ${(data.total_kzt || 0).toLocaleString()} ₸`
        });
      }
    },
    onError: (error: Error) => {
      console.error('Error backfilling commissions:', error);
      toast.error('Ошибка доначисления', {
        description: error.message
      });
    }
  });
}

/**
 * Hook to backfill all missing S1 commissions system-wide
 */
export function useBackfillAllCommissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ dryRun = true }: { dryRun?: boolean }) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('backfill_missing_s1_commissions', {
        p_admin_id: user.id,
        p_dry_run: dryRun
      });

      if (error) throw error;
      return data as unknown as BackfillResult;
    },
    onSuccess: (data, variables) => {
      if (!variables.dryRun) {
        queryClient.invalidateQueries({ queryKey: ['sponsors-with-missing-commissions'] });
        queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['balance'] });
        
        toast.success('Все комиссии доначислены', {
          description: `Обработано: ${data.subscriptions_processed}, создано: ${data.commissions_created}`
        });
      }
    },
    onError: (error: Error) => {
      console.error('Error backfilling all commissions:', error);
      toast.error('Ошибка массового доначисления', {
        description: error.message
      });
    }
  });
}

/**
 * Hook to backfill missing multilevel (L1-L5) commissions
 */
export function useBackfillMultilevelCommissions() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ dryRun = true, targetUserId }: { dryRun?: boolean; targetUserId?: string }) => {
      if (!user?.id) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('backfill_missing_multilevel_commissions', {
        p_admin_id: user.id,
        p_dry_run: dryRun,
        p_target_user_id: targetUserId || null
      });

      if (error) throw error;
      return data as unknown as BackfillResult;
    },
    onSuccess: (data, variables) => {
      if (!variables.dryRun) {
        queryClient.invalidateQueries({ queryKey: ['sponsors-with-missing-commissions'] });
        queryClient.invalidateQueries({ queryKey: ['commission-structure'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['balance'] });
        queryClient.invalidateQueries({ queryKey: ['network-tree'] });
        
        toast.success('Многоуровневые комиссии доначислены', {
          description: `Создано комиссий: ${data.commissions_created}, сумма: ${(data.total_kzt || 0).toLocaleString()} ₸`
        });
      }
    },
    onError: (error: Error) => {
      console.error('Error backfilling multilevel commissions:', error);
      toast.error('Ошибка доначисления многоуровневых комиссий', {
        description: error.message
      });
    }
  });
}
