import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export function useActivationThreshold() {
  return useQuery({
    queryKey: ["activation-threshold"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("shop_settings")
        .select("monthly_activation_required_kzt, monthly_activation_required_usd")
        .single();
      
      if (error) throw error;
      
      // All amounts in whole units (KZT as tenge, USD as dollars)
      return {
        kzt: data?.monthly_activation_required_kzt || 20000,
        usd: data?.monthly_activation_required_usd || 40
      };
    },
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}
