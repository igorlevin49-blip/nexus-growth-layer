import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

// Type matching the get_referral_network_from_table function return
interface NetworkMemberRaw {
  id: string;
  full_name: string | null;
  avatar_url: string | null;
  level: number;
  parent_id: string | null;
  subscription_status: string | null;
  subscription_expires_at: string | null;
  personal_activation_volume: number;
  has_commission_received: boolean;
  no_commission_reason: string | null;
  commission_frozen_until: string | null;
  is_activated: boolean;
  created_at: string | null;
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
    user_id: raw.id,
    partner_id: raw.id,
    level: raw.level,
    full_name: raw.full_name,
    email: null,
    phone: null,
    avatar_url: raw.avatar_url,
    subscription_status: raw.subscription_status,
    subscription_expires_at: raw.subscription_expires_at,
    monthly_activation_met: raw.is_activated,
    referral_code: '',
    created_at: raw.created_at || '',
    direct_referrals: 0,
    total_team: 0,
    monthly_volume: raw.personal_activation_volume,
    parent_partner_id: raw.parent_id,
    parent_user_id: raw.parent_id,
    has_commission_received: raw.has_commission_received,
    no_commission_reason: raw.no_commission_reason,
    commission_status: raw.has_commission_received ? 'received' : null,
    commission_frozen_until: raw.commission_frozen_until,
    is_activated: raw.is_activated,
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
