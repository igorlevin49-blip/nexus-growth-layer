import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

/**
 * Commission Structure Hook - UPDATED
 * 
 * Now uses get_commission_structure_stats RPC function
 * which correctly calculates all statistics recursively
 */

export interface CommissionLevel {
  level: number;
  percent: number;
  earned: number;
  frozen: number;
  volume: number;
  partners_count: number;
  status: 'active' | 'frozen' | 'locked';
  unlock_requirement?: string;
}

interface UseCommissionStructureOptions {
  structureType?: 1 | 2;
  startDate?: Date;
  endDate?: Date;
}

export function useCommissionStructure(options: UseCommissionStructureOptions = {}) {
  const { structureType = 1, startDate, endDate } = options;

  return useQuery({
    queryKey: ['commission-structure', structureType, startDate, endDate],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Use new RPC function that correctly calculates everything
      const { data, error } = await supabase.rpc('get_commission_structure_stats', {
        p_user_id: user.id,
        p_structure_type: structureType,
        p_start_date: startDate?.toISOString() || null,
        p_end_date: endDate?.toISOString() || null
      });

      if (error) throw error;

      // Data is already in whole KZT, map from DB naming to interface naming
      return (data || []).map(level => ({
        level: level.level,
        percent: level.percent,
        earned: level.earned_cents,  // DB returns _cents but values are in whole KZT
        frozen: level.frozen_cents,  // DB returns _cents but values are in whole KZT
        volume: level.volume_cents,  // DB returns _cents but values are in whole KZT
        partners_count: level.partners_count,
        status: level.status as 'active' | 'frozen' | 'locked',
        unlock_requirement: level.unlock_requirement
      })) as CommissionLevel[];
    },
    staleTime: 30000,
    refetchOnMount: 'always'
  });
}
