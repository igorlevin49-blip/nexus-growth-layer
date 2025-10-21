import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface Withdrawal {
  id: string;
  user_id: string;
  method_id: string | null;
  amount_cents: number;
  fee_cents: number;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled';
  transaction_id: string | null;
  created_at: string;
  processed_at: string | null;
}

export function useWithdrawals() {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['withdrawals'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('withdrawals')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false });

      if (error) throw error;
      return (data || []) as Withdrawal[];
    }
  });

  const createWithdrawal = useMutation({
    mutationFn: async ({ amount_cents, method_id }: { amount_cents: number; method_id: string }) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Create withdrawal record
      const { data: withdrawal, error: withdrawalError } = await supabase
        .from('withdrawals')
        .insert([{
          user_id: user.id,
          amount_cents,
          method_id,
          fee_cents: 0,
          status: 'processing'
        }])
        .select()
        .single();

      if (withdrawalError) throw withdrawalError;

      // Create negative transaction
      const { error: transactionError } = await supabase
        .from('transactions')
        .insert([{
          user_id: user.id,
          type: 'withdrawal',
          amount_cents,
          status: 'processing',
          source_id: withdrawal.id,
          source_ref: `withdrawal_${withdrawal.id}`
        }]);

      if (transactionError) throw transactionError;

      return withdrawal;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['withdrawals'] });
      queryClient.invalidateQueries({ queryKey: ['balance'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      toast.success('Запрос на вывод средств создан');
    },
    onError: () => {
      toast.error('Ошибка при создании запроса на вывод');
    }
  });

  return {
    ...query,
    createWithdrawal
  };
}
