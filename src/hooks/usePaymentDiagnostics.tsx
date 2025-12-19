import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface PaymentError {
  id: string;
  type: 'subscription' | 'order';
  record_id: string;
  user_id: string;
  user_email: string | null;
  user_name: string | null;
  amount_kzt: number;
  status: string;
  error_type: string;
  error_details: Record<string, unknown>;
  created_at: string;
}

export function usePaymentDiagnostics() {
  return useQuery({
    queryKey: ['payment-diagnostics'],
    queryFn: async () => {
      // Get commission_skipped events from activity_log
      const { data: skippedCommissions, error: skippedError } = await supabase
        .from('activity_log')
        .select(`
          id,
          user_id,
          type,
          payload,
          created_at
        `)
        .eq('type', 'commission_skipped')
        .order('created_at', { ascending: false })
        .limit(100);

      if (skippedError) throw skippedError;

      // Get pending subscriptions that might have issues
      const { data: pendingSubscriptions, error: subsError } = await supabase
        .from('subscriptions')
        .select(`
          id,
          user_id,
          amount_kzt,
          status,
          created_at,
          profiles!subscriptions_user_id_fkey1 (
            email,
            full_name
          )
        `)
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
        .limit(50);

      if (subsError) throw subsError;

      // Get pending orders that might have issues
      const { data: pendingOrders, error: ordersError } = await supabase
        .from('orders')
        .select(`
          id,
          user_id,
          total_kzt,
          status,
          created_at
        `)
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
        .limit(50);

      if (ordersError) throw ordersError;

      // Combine into unified error list
      const errors: PaymentError[] = [];

      // Add skipped commissions as errors
      for (const log of skippedCommissions || []) {
        const payload = log.payload as Record<string, unknown> || {};
        errors.push({
          id: log.id,
          type: payload.subscription_id ? 'subscription' : 'order',
          record_id: (payload.subscription_id || payload.order_id || '') as string,
          user_id: log.user_id,
          user_email: null,
          user_name: null,
          amount_kzt: (payload.would_be_amount_kzt || 0) as number,
          status: 'skipped',
          error_type: (payload.reason || 'unknown') as string,
          error_details: payload,
          created_at: log.created_at
        });
      }

      // Get profiles for user info
      const userIds = [...new Set(errors.map(e => e.user_id))];
      if (userIds.length > 0) {
        const { data: profiles } = await supabase
          .from('profiles')
          .select('id, email, full_name')
          .in('id', userIds);

        const profileMap = new Map((profiles || []).map(p => [p.id, p]));
        for (const error of errors) {
          const profile = profileMap.get(error.user_id);
          if (profile) {
            error.user_email = profile.email;
            error.user_name = profile.full_name;
          }
        }
      }

      return {
        errors: errors.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()),
        pendingSubscriptions: pendingSubscriptions || [],
        pendingOrders: pendingOrders || [],
        stats: {
          totalErrors: errors.length,
          skippedCommissions: skippedCommissions?.length || 0,
          pendingSubscriptions: pendingSubscriptions?.length || 0,
          pendingOrders: pendingOrders?.length || 0
        }
      };
    },
    staleTime: 30000,
    refetchInterval: 60000
  });
}

export function useReprocessPayment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ recordType, recordId }: { recordType: 'subscription' | 'order', recordId: string }) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('process_payment_completion', {
        p_record_type: recordType,
        p_record_id: recordId,
        p_admin_id: user.id,
        p_comment: 'Повторная обработка из диагностики'
      });

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payment-diagnostics'] });
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      toast.success('Платёж успешно обработан');
    },
    onError: (error: Error) => {
      toast.error(`Ошибка обработки: ${error.message}`);
    }
  });
}
