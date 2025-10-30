import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface FlagTestDataParams {
  startDate: string;
  endDate: string;
  userIds?: string[];
  dryRun: boolean;
}

interface PurgeTestDataParams {
  dryRun: boolean;
  confirmationPhrase?: string;
}

interface TestDataStats {
  orders: number;
  subscriptions: number;
  transactions: number;
  withdrawals: number;
  dry_run: boolean;
}

export function useAdminUsers() {
  return useQuery({
    queryKey: ['admin-users'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('user_roles')
        .select('user_id, profiles!inner(full_name, email)')
        .in('role', ['admin', 'superadmin']);
      
      if (error) throw error;
      return data.map(ur => ({
        id: ur.user_id,
        name: (ur.profiles as any)?.full_name || 'Unknown',
        email: (ur.profiles as any)?.email || ''
      }));
    }
  });
}

export function useFlagTestData() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: FlagTestDataParams) => {
      const { data, error } = await supabase.rpc('flag_test_data', {
        p_start_date: params.startDate,
        p_end_date: params.endDate,
        p_user_ids: params.userIds || null,
        p_dry_run: params.dryRun
      });

      if (error) throw error;
      return data as unknown as TestDataStats;
    },
    onSuccess: (data) => {
      if (!data.dry_run) {
        queryClient.invalidateQueries({ queryKey: ['orders'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
        queryClient.invalidateQueries({ queryKey: ['withdrawals'] });
        toast.success('Тестовые данные помечены');
      }
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при пометке данных');
    }
  });
}

export function usePurgeTestData() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: PurgeTestDataParams) => {
      const { data, error } = await supabase.rpc('purge_test_data', {
        p_dry_run: params.dryRun,
        p_confirmation_phrase: params.confirmationPhrase || ''
      });

      if (error) throw error;
      return data as unknown as TestDataStats;
    },
    onSuccess: (data) => {
      if (!data.dry_run) {
        queryClient.invalidateQueries();
        toast.success('Тестовые данные удалены');
      }
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при удалении данных');
    }
  });
}
