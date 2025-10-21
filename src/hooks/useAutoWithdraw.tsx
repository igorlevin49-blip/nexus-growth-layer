import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface AutoWithdrawRule {
  user_id: string;
  enabled: boolean;
  threshold_cents: number;
  schedule: 'daily' | 'weekly' | 'monthly';
  min_amount_cents: number;
  method_id: string | null;
  created_at: string;
  updated_at: string;
}

export function useAutoWithdraw() {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['auto-withdraw'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('auto_withdraw_rules')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();

      if (error) throw error;
      return data as AutoWithdrawRule | null;
    }
  });

  const updateRule = useMutation({
    mutationFn: async (rule: Partial<Omit<AutoWithdrawRule, 'user_id' | 'created_at' | 'updated_at'>>) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('auto_withdraw_rules')
        .upsert([{ ...rule, user_id: user.id }], { onConflict: 'user_id' })
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['auto-withdraw'] });
      toast.success('Настройки автовывода обновлены');
    },
    onError: () => {
      toast.error('Ошибка при обновлении настроек автовывода');
    }
  });

  return {
    ...query,
    updateRule
  };
}
