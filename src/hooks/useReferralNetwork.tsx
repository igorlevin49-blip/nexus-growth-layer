import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

// Type matching the get_referral_network_from_table function return
interface ReferralMemberRaw {
  user_id: string;
  partner_id: string;
  email: string | null;
  full_name: string | null;
  referral_code: string;
  subscription_status: string | null;
  monthly_activation_met: boolean;
  level: number;
  structure_type: number;
  created_at: string | null;
  has_commission_received: boolean;
  no_commission_reason: string | null;
  parent_partner_id: string | null;
}

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
  structure_type?: number;
  avatar_url?: string | null;
  direct_referrals?: number;
  total_team?: number;
  monthly_volume?: number;
  has_commission_received?: boolean;
  no_commission_reason?: string | null;
  commission_frozen_until?: string | null;
  is_activated?: boolean;
  parent_partner_id?: string | null;
};

// Map raw DB response to ReferralMember interface
function mapToReferralMember(raw: ReferralMemberRaw): ReferralMember {
  return {
    user_id: raw.user_id,
    partner_id: raw.partner_id || raw.user_id,
    level: raw.level,
    full_name: raw.full_name || '',
    email: raw.email,
    referral_code: raw.referral_code || '',
    subscription_status: raw.subscription_status || 'inactive',
    monthly_activation_met: raw.monthly_activation_met,
    created_at: raw.created_at || '',
    avatar_url: null,
    direct_referrals: 0,
    total_team: 0,
    monthly_volume: 0,
    has_commission_received: raw.has_commission_received,
    no_commission_reason: raw.no_commission_reason,
    commission_frozen_until: null,
    is_activated: raw.monthly_activation_met,
    structure_type: raw.structure_type,
    parent_partner_id: raw.parent_partner_id,
  };
}

export const useReferralNetwork = (structureType: 1 | 2 = 1, maxLevels: number = 10) => {
  const { user } = useAuth();

  return useQuery({
    queryKey: ['referral-network', user?.id, structureType, maxLevels],
    queryFn: async () => {
      if (!user?.id) return [];

      const { data, error } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: user.id,
        p_max_levels: maxLevels,
        p_structure_type: structureType,
      });

      if (error) {
        console.error('Error fetching referral network:', error);
        throw error;
      }

      const rawMembers = (data || []) as ReferralMemberRaw[];
      return rawMembers.map(mapToReferralMember);
    },
    enabled: !!user?.id,
  });
};
