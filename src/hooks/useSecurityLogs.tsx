import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface SecurityLog {
  id: string;
  user_id: string;
  type: string;
  payload: any;
  created_at: string;
  user?: {
    full_name: string | null;
    email: string | null;
  };
}

const SECURITY_LOG_TYPES = [
  'referral_bound',
  'referral_bind_failed',
  'admin_bind_sponsor_success',
  'admin_bind_sponsor_failed',
  'account_restored',
  'registration',
  'subscription_activated'
];

export function useSecurityLogs(days: number = 7) {
  return useQuery({
    queryKey: ['security-logs', days],
    queryFn: async () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - days);

      const { data, error } = await supabase
        .from('activity_log')
        .select(`
          id,
          user_id,
          type,
          payload,
          created_at
        `)
        .in('type', SECURITY_LOG_TYPES)
        .gte('created_at', startDate.toISOString())
        .order('created_at', { ascending: false })
        .limit(500);

      if (error) throw error;

      // Fetch user info separately
      const userIds = [...new Set((data || []).map(log => log.user_id))];
      
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, email')
        .in('id', userIds);

      const profilesMap = new Map(
        (profiles || []).map(p => [p.id, { full_name: p.full_name, email: p.email }])
      );

      return (data || []).map(log => ({
        ...log,
        user: profilesMap.get(log.user_id) || null
      })) as SecurityLog[];
    },
  });
}

export function useSecurityStats(days: number = 7) {
  return useQuery({
    queryKey: ['security-stats', days],
    queryFn: async () => {
      const startDate = new Date();
      startDate.setDate(startDate.getDate() - days);

      const { data, error } = await supabase
        .from('activity_log')
        .select('type')
        .in('type', SECURITY_LOG_TYPES)
        .gte('created_at', startDate.toISOString());

      if (error) throw error;

      const stats = {
        total: data?.length || 0,
        successful_binds: 0,
        failed_binds: 0,
        admin_actions: 0,
        registrations: 0,
        subscriptions: 0,
        restorations: 0
      };

      (data || []).forEach(log => {
        switch (log.type) {
          case 'referral_bound':
            stats.successful_binds++;
            break;
          case 'referral_bind_failed':
            stats.failed_binds++;
            break;
          case 'admin_bind_sponsor_success':
          case 'admin_bind_sponsor_failed':
            stats.admin_actions++;
            break;
          case 'registration':
            stats.registrations++;
            break;
          case 'subscription_activated':
            stats.subscriptions++;
            break;
          case 'account_restored':
            stats.restorations++;
            break;
        }
      });

      return stats;
    },
  });
}
