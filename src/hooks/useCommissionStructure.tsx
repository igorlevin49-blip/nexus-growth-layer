import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface CommissionLevel {
  id: string;
  plan_id: string;
  structure_type: 'primary' | 'secondary';
  level: number;
  percent: number;
  description: string | null;
  volume?: number; // calculated
  earned?: number; // calculated
}

interface UseCommissionStructureOptions {
  structureType?: 'primary' | 'secondary' | 'all';
  startDate?: Date;
  endDate?: Date;
}

export function useCommissionStructure(options: UseCommissionStructureOptions = {}) {
  const { structureType = 'all', startDate, endDate } = options;

  return useQuery({
    queryKey: ['commission-structure', structureType, startDate, endDate],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Get commission plan levels
      let levelsQuery = supabase
        .from('commission_plan_levels')
        .select('*')
        .eq('plan_id', 'default')
        .order('level', { ascending: true });

      if (structureType !== 'all') {
        levelsQuery = levelsQuery.eq('structure_type', structureType);
      }

      const { data: levels, error: levelsError } = await levelsQuery;
      if (levelsError) throw levelsError;

      // Calculate volume and earnings for each level
      const enrichedLevels = await Promise.all(
        (levels || []).map(async (level) => {
          // Get transactions for this level
          let transQuery = supabase
            .from('transactions')
            .select('amount_cents')
            .eq('user_id', user.id)
            .eq('level', level.level)
            .eq('structure_type', level.structure_type)
            .eq('type', 'commission')
            .eq('status', 'completed');

          if (startDate) {
            transQuery = transQuery.gte('created_at', startDate.toISOString());
          }
          if (endDate) {
            transQuery = transQuery.lte('created_at', endDate.toISOString());
          }

          const { data: trans } = await transQuery;
          
          const earned = (trans || []).reduce((sum, t) => sum + (t.amount_cents || 0), 0);
          const volume = earned > 0 ? Math.round(earned / (level.percent / 100)) : 0;

          return {
            ...level,
            volume,
            earned
          } as CommissionLevel;
        })
      );

      return enrichedLevels;
    }
  });
}
