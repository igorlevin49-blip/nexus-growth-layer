import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";

export function usePendingOrdersCount() {
  const { userRole } = useAuth();

  return useQuery({
    queryKey: ['pending-orders-count'],
    queryFn: async () => {
      const { count, error } = await supabase
        .from('orders')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending')
        .or('is_archived.is.null,is_archived.eq.false');

      if (error) throw error;
      return count || 0;
    },
    enabled: userRole === 'admin' || userRole === 'superadmin',
    refetchInterval: 30000,
  });
}
