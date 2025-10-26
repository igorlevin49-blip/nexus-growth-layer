import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface MLMRule {
  id: string;
  structure_type: 1 | 2;
  level: number;
  percent: number;
  plan_id: string;
  effective_from: string;
}

export function useMLMRules(structureType: 1 | 2) {
  return useQuery({
    queryKey: ['mlm-rules', structureType],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('mlm_commission_rules')
        .select('*')
        .eq('structure_type', structureType)
        .eq('plan_id', 'default')
        .order('level', { ascending: true });

      if (error) throw error;
      return (data || []) as MLMRule[];
    }
  });
}
