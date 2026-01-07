import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

/**
 * Admin Stats - using KZT (whole tenge) for all amounts
 */

export interface AdminGlobalStats {
  total_revenue_kzt: number;
  active_users_count: number;
  orders_count: number;
  avg_order_kzt: number;
  subscriptions_count: number;
  frozen_users_count: number;
}

export interface AdminStructureStats {
  level: number;
  percent: number;
  transactions_count: number;
  total_amount_kzt: number;
  frozen_amount_kzt: number;
  available_amount_kzt: number;
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
      
      // Map from DB naming (_cents) to interface naming (_kzt)
      const raw: any = data?.[0] || {};
      return {
        total_revenue_kzt: raw.total_revenue_cents || 0,
        active_users_count: raw.active_users_count || 0,
        orders_count: raw.orders_count || 0,
        avg_order_kzt: raw.avg_order_cents || 0,
        subscriptions_count: raw.subscriptions_count || 0,
        frozen_users_count: raw.frozen_users_count || 0
      } as AdminGlobalStats;
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
      
      // Map from DB naming (_cents) to interface naming (_kzt)
      return (data || []).map((row: any) => ({
        level: row.level,
        percent: row.percent,
        transactions_count: row.transactions_count,
        total_amount_kzt: row.total_amount_cents || 0,
        frozen_amount_kzt: row.frozen_amount_cents || 0,
        available_amount_kzt: row.available_amount_cents || 0,
        pass_up_count: row.pass_up_count || 0
      })) as AdminStructureStats[];
    },
    staleTime: 60000,
    refetchOnMount: 'always'
  });
}