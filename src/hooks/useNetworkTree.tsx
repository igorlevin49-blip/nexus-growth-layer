import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

// Type matching the get_referral_network_from_table function return
interface NetworkMemberRaw {
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

export interface NetworkMember {
  user_id: string;
  partner_id: string;
  level: number;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  avatar_url: string | null;
  subscription_status: string | null;
  subscription_expires_at: string | null;
  monthly_activation_met: boolean | null;
  referral_code: string;
  created_at: string;
  direct_referrals: number;
  total_team: number;
  monthly_volume: number;
  parent_partner_id: string | null;
  parent_user_id: string | null;
  has_commission_received: boolean | null;
  no_commission_reason: string | null;
  commission_status: string | null;
  commission_frozen_until: string | null;
  is_activated?: boolean;
}

// Map raw DB response to NetworkMember interface
function mapToNetworkMember(raw: NetworkMemberRaw): NetworkMember {
  return {
    user_id: raw.user_id,
    partner_id: raw.partner_id || raw.user_id,
    level: raw.level,
    full_name: raw.full_name,
    email: raw.email,
    phone: null,
    avatar_url: null,
    subscription_status: raw.subscription_status,
    subscription_expires_at: null,
    monthly_activation_met: raw.monthly_activation_met,
    referral_code: raw.referral_code || '',
    created_at: raw.created_at || '',
    direct_referrals: 0,
    total_team: 0,
    monthly_volume: 0,
    parent_partner_id: raw.parent_partner_id,
    parent_user_id: null,
    has_commission_received: raw.has_commission_received,
    no_commission_reason: raw.no_commission_reason,
    commission_status: raw.has_commission_received ? 'received' : null,
    commission_frozen_until: null,
    is_activated: raw.monthly_activation_met,
  };
}

export function useNetworkTree(maxLevel: number = 10, structureType: 1 | 2 = 1) {
  return useQuery({
    queryKey: ['network-tree', maxLevel, structureType],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: user.id,
        p_max_levels: maxLevel,
        p_structure_type: structureType
      });

      if (error) throw error;
      
      const rawMembers = (data || []) as NetworkMemberRaw[];
      const members = rawMembers.map(mapToNetworkMember);
      
      // Debug log to verify data
      console.log(`[NetworkTree] Structure ${structureType}, loaded ${members.length} members`);
      
      return members;
    },
    staleTime: 10000,
    placeholderData: [],
    refetchOnMount: 'always',
    refetchOnWindowFocus: true
  });
}
