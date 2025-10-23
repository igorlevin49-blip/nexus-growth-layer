import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

export type ReferralMember = {
  user_id: string;
  partner_id: string;
  level: number;
  full_name: string;
  email: string | null;
  referral_code: string;
  subscription_status: string;
  monthly_activation_met: boolean;
  created_at: string;
  structure_type: number;
};

export const useReferralNetwork = (structureType: 1 | 2 = 1, maxLevels: number = 10) => {
  const { user } = useAuth();

  return useQuery({
    queryKey: ['referral-network', user?.id, structureType, maxLevels],
    queryFn: async () => {
      if (!user?.id) return [];

      const { data, error } = await supabase.rpc('get_referral_network', {
        root_user_id: user.id,
        structure_type_param: structureType,
        max_levels: maxLevels,
      });

      if (error) {
        console.error('Error fetching referral network:', error);
        throw error;
      }

      return (data || []) as ReferralMember[];
    },
    enabled: !!user?.id,
  });
};
