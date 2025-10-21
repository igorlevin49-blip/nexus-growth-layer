import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface Balance {
  available_cents: number;
  frozen_cents: number;
  pending_cents: number;
  withdrawn_cents: number;
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
        available_cents: 0,
        frozen_cents: 0,
        pending_cents: 0,
        withdrawn_cents: 0
      };

      return balance as Balance;
    }
  });
}
