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
      
      const row = (data?.[0] as any) || null;

      const balance: Balance = {
        // DB function returns *_cents naming but values are in whole KZT
        available_kzt: Number(row?.available_kzt ?? row?.available_cents ?? 0),
        frozen_kzt: Number(row?.frozen_kzt ?? row?.frozen_cents ?? 0),
        pending_kzt: Number(row?.pending_kzt ?? row?.pending_cents ?? 0),
        withdrawn_kzt: Number(row?.withdrawn_kzt ?? row?.withdrawn_cents ?? 0),
      };

      return balance;
    },
    staleTime: 30000,
    refetchOnMount: 'always'
  });
}
