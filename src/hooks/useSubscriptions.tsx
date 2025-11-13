import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "./useAuth";

export interface Subscription {
  id: string;
  user_id: string;
  status: 'pending' | 'active' | 'frozen' | 'cancelled';
  amount_usd: number;
  amount_kzt: number;
  payment_method?: string;
  payment_confirmed_by?: string;
  payment_confirmed_at?: string;
  approval_comment?: string;
  started_at?: string;
  expires_at?: string;
  created_at: string;
  updated_at: string;
  profiles?: {
    full_name: string;
    email: string;
  };
}

export function useSubscriptions(showArchived: boolean = false) {
  const { user, userRole } = useAuth();
  
  return useQuery({
    queryKey: ['subscriptions', showArchived, userRole],
    queryFn: async () => {
      let query = supabase
        .from('subscriptions')
        .select('*')
        .limit(1000);

      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      const { data, error } = await query;
      if (error) throw error;
      
      // Fetch profiles separately
      const subscriptionsWithProfiles = await Promise.all(
        (data || []).map(async (sub) => {
          const { data: profile } = await supabase
            .from('profiles')
            .select('full_name, email')
            .eq('id', sub.user_id)
            .single();
          
          return {
            ...sub,
            profiles: profile || { full_name: '', email: '' }
          };
        })
      );
      
      // Sort: pending first, then paid, then others
      const sortedSubs = subscriptionsWithProfiles.sort((a, b) => {
        const statusOrder = { pending: 0, active: 1, paid: 1, frozen: 2, cancelled: 3, declined: 3 };
        const orderA = statusOrder[a.status as keyof typeof statusOrder] ?? 99;
        const orderB = statusOrder[b.status as keyof typeof statusOrder] ?? 99;
        if (orderA !== orderB) return orderA - orderB;
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
      
      return sortedSubs as Subscription[];
    },
    enabled: !!user
  });
}

export function useUserSubscription() {
  const { user } = useAuth();
  
  return useQuery({
    queryKey: ['user-subscription', user?.id],
    queryFn: async () => {
      if (!user) return null;
      
      const { data, error } = await supabase
        .from('subscriptions')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();

      if (error && error.code !== 'PGRST116') throw error;
      return data as Subscription | null;
    },
    enabled: !!user
  });
}

export function useConfirmPayment() {
  const queryClient = useQueryClient();
  const { user } = useAuth();

  return useMutation({
    mutationFn: async ({
      id,
      type,
      comment
    }: {
      id: string;
      type: 'subscription' | 'order';
      comment?: string;
    }) => {
      console.log(`[CONFIRM_PAYMENT] Starting ${type} confirmation for ID:`, id);
      
      // UNIFIED HANDLER: Use RPC functions to ensure proper commission calculation
      if (type === 'subscription') {
        console.log('[CONFIRM_PAYMENT] Calling approve_subscription_payment RPC...');
        
        const { data, error } = await supabase.rpc('approve_subscription_payment', {
          p_subscription_id: id,
          p_admin_id: user?.id || '',
          p_comment: comment || ''
        });

        if (error) {
          console.error('[CONFIRM_PAYMENT] RPC error:', error);
          throw error;
        }

        const result = data as { success?: boolean; error?: string } | null;
        
        if (!result?.success) {
          console.error('[CONFIRM_PAYMENT] RPC returned error:', result?.error);
          throw new Error(result?.error || 'Не удалось подтвердить подписку');
        }
        
        console.log('[CONFIRM_PAYMENT] Subscription confirmed successfully');
      } else {
        console.log('[CONFIRM_PAYMENT] Calling process_payment_completion RPC for order...');
        
        const { data, error } = await supabase.rpc('process_payment_completion', {
          p_record_type: 'order',
          p_record_id: id,
          p_payment_method: 'manual',
          p_admin_id: user?.id || '',
          p_comment: comment || ''
        });

        if (error) {
          console.error('[CONFIRM_PAYMENT] RPC error:', error);
          throw error;
        }

        const result = data as { success?: boolean; error?: string; message?: string } | null;
        
        if (!result?.success) {
          console.error('[CONFIRM_PAYMENT] RPC returned error:', result?.error);
          throw new Error(result?.error || 'Не удалось подтвердить заказ');
        }
        
        console.log('[CONFIRM_PAYMENT] Order confirmed successfully:', result.message);
      }
    },
    onSuccess: (_, variables) => {
      console.log(`[CONFIRM_PAYMENT] Invalidating queries after ${variables.type} confirmation`);
      
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      queryClient.invalidateQueries({ queryKey: ['balance'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      queryClient.invalidateQueries({ queryKey: ['profile'] });
      queryClient.invalidateQueries({ queryKey: ['network-tree'] });
      
      toast.success(
        variables.type === 'subscription' 
          ? 'Подписка подтверждена. Комиссии начислены.' 
          : 'Заказ оплачен. Комиссии начислены.'
      );
    },
    onError: (error) => {
      console.error('[CONFIRM_PAYMENT] Error:', error);
      toast.error(`Ошибка подтверждения: ${error.message}`);
    }
  });
}
