import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface ActivityLog {
  id: string;
  user_id: string;
  type: string;
  payload: any;
  created_at: string;
  user_name?: string;
  user_email?: string;
}

interface UseNetworkActivityOptions {
  types?: string[];
  startDate?: Date;
  endDate?: Date;
  limit?: number;
  offset?: number;
}

export function useNetworkActivity(options: UseNetworkActivityOptions = {}) {
  const { types, startDate, endDate, limit = 50, offset = 0 } = options;

  return useQuery({
    queryKey: ['network-activity', types, startDate, endDate, limit, offset],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // First get user's network member IDs
      const { data: networkData, error: networkError } = await supabase.rpc('get_referral_network_from_table', {
        root_user_id: user.id,
        p_max_levels: 10,
        // p_structure_type omitted -> default (1)
      });

      if (networkError) throw networkError;
      
      const networkUserIds = (networkData || []).map((m: any) => m.id as string);
      
      // If user has no network, return empty array
      if (networkUserIds.length === 0) {
        return [] as ActivityLog[];
      }

      let query = supabase
        .from('activity_log')
        .select(`
          id,
          user_id,
          type,
          payload,
          created_at,
          profiles!inner(full_name, email)
        `)
        .in('user_id', networkUserIds)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (types && types.length > 0) {
        query = query.in('type', types);
      }

      if (startDate) {
        query = query.gte('created_at', startDate.toISOString());
      }

      if (endDate) {
        query = query.lte('created_at', endDate.toISOString());
      }

      const { data, error } = await query;

      if (error) throw error;

      return (data || []).map(log => ({
        id: log.id,
        user_id: log.user_id,
        type: log.type,
        payload: log.payload,
        created_at: log.created_at,
        user_name: (log.profiles as any)?.full_name,
        user_email: (log.profiles as any)?.email
      })) as ActivityLog[];
    }
  });
}
