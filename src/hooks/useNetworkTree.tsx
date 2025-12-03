import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface NetworkMember {
  user_id: string;
  partner_id: string;
  level: number;
  full_name: string | null;
  email: string | null;
  avatar_url: string | null;
  subscription_status: string | null;
  monthly_activation_met: boolean | null;
  referral_code: string;
  created_at: string;
  direct_referrals: number;
  total_team: number;
  monthly_volume: number;
}

export function useNetworkTree(maxLevel: number = 10, structureType: 1 | 2 = 1) {
  return useQuery({
    queryKey: ['network-tree', maxLevel, structureType],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: user.id,
        max_level: maxLevel,
        p_structure_type: structureType
      });

      if (error) throw error;
      return (data || []) as NetworkMember[];
    },
    staleTime: 30000,
    placeholderData: [],
    refetchOnMount: 'always'
  });
}
