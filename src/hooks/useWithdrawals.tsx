import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface Withdrawal {
  id: string;
  user_id: string;
  method_id: string | null;
  amount_kzt: number;
  fee_kzt: number;
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
      // Map from DB column names until types.ts is regenerated
      return (data || []).map((w: any) => ({
        ...w,
        amount_kzt: w.amount_kzt ?? w.amount_cents ?? 0,
        fee_kzt: w.fee_kzt ?? w.fee_cents ?? 0
      })) as Withdrawal[];
    }
  });

  const createWithdrawal = useMutation({
    mutationFn: async ({ amount_kzt, method_id }: { amount_kzt: number; method_id: string }) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Используем атомарную серверную функцию
      const { data, error } = await supabase.rpc('create_user_withdrawal' as any, {
        p_user_id: user.id,
        p_amount_kzt: amount_kzt,
        p_method_id: method_id
      });

      if (error) throw error;

      // Проверяем результат функции
      const result = data as { success: boolean; message?: string; withdrawal_id?: string };
      if (!result.success) {
        const errorMessage = result.message || 'Ошибка при создании вывода';
        throw new Error(errorMessage);
      }

      return result;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['withdrawals'] });
      queryClient.invalidateQueries({ queryKey: ['balance'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      toast.success('Запрос на вывод средств создан');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Ошибка при создании запроса на вывод');
    }
  });

  return {
    ...query,
    createWithdrawal
  };
}
