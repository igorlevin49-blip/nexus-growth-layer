import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface NetworkStats {
  total_partners: number;
  active_partners: number;
  frozen_partners: number;
  max_level: number;
  new_this_month: number;
  activations_this_month: number;
  volume_this_month: number;
  commissions_this_month: number;
}

export function useNetworkStats(structureType: 1 | 2 = 1) {
  return useQuery({
    queryKey: ['network-stats', structureType],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('get_network_stats', {
        user_id_param: user.id,
        p_structure_type: structureType
      });

      if (error) throw error;
      return data?.[0] as NetworkStats || {
        total_partners: 0,
        active_partners: 0,
        frozen_partners: 0,
        max_level: 0,
        new_this_month: 0,
        activations_this_month: 0,
        volume_this_month: 0,
        commissions_this_month: 0
      };
    },
    staleTime: 30000,
    refetchOnMount: 'always'
  });
}
