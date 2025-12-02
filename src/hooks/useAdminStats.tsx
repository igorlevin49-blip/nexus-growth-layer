import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface AdminGlobalStats {
  total_revenue_cents: number;
  active_users_count: number;
  orders_count: number;
  avg_order_cents: number;
  subscriptions_count: number;
  frozen_users_count: number;
}

export interface AdminStructureStats {
  level: number;
  percent: number;
  transactions_count: number;
  total_amount_cents: number;
  frozen_amount_cents: number;
  pass_up_count: number;
}

export function useAdminGlobalStats(startDate?: Date, endDate?: Date, showArchived: boolean = false) {
  return useQuery({
    queryKey: ['admin-global-stats', startDate, endDate, showArchived],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_admin_global_stats', {
        start_date: startDate?.toISOString() || new Date(new Date().setDate(1)).toISOString(),
        end_date: endDate?.toISOString() || new Date().toISOString()
      });

      if (error) throw error;
      return data?.[0] as AdminGlobalStats || {
        total_revenue_cents: 0,
        active_users_count: 0,
        orders_count: 0,
        avg_order_cents: 0,
        subscriptions_count: 0,
        frozen_users_count: 0
      };
    },
    staleTime: 60000,
    refetchOnMount: 'always'
  });
}

export function useAdminStructureStats(
  structureType: 1 | 2,
  startDate?: Date,
  endDate?: Date
) {
  return useQuery({
    queryKey: ['admin-structure-stats', structureType, startDate, endDate],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_admin_structure_stats', {
        structure_type_param: structureType,
        start_date: startDate?.toISOString() || new Date(new Date().setDate(1)).toISOString(),
        end_date: endDate?.toISOString() || new Date().toISOString()
      });

      if (error) throw error;
      return (data || []) as AdminStructureStats[];
    },
    staleTime: 60000,
    refetchOnMount: 'always'
  });
}