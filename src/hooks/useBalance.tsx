import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface Balance {
  available_kzt: number;
  frozen_kzt: number;
  pending_kzt: number;
  withdrawn_kzt: number;
}

export function useBalance() {
  return useQuery({
    queryKey: ['balance'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('get_user_balance', {
        p_user_id: user.id
      });

      if (error) throw error;
      
      const balance = data?.[0] || {
        available_kzt: 0,
        frozen_kzt: 0,
        pending_kzt: 0,
        withdrawn_kzt: 0
      };

      return balance as Balance;
    },
    staleTime: 30000,
    refetchOnMount: 'always'
  });
}
