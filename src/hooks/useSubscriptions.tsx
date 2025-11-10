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
  admin_comment?: string;
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
      if (type === 'subscription') {
        // Confirm subscription
        const { error } = await supabase
          .from('subscriptions')
          .update({
            status: 'active',
            payment_confirmed_by: user?.id,
            payment_confirmed_at: new Date().toISOString(),
            admin_comment: comment,
            started_at: new Date().toISOString(),
            expires_at: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString() // 12 months
          })
          .eq('id', id);

        if (error) throw error;

        // Log admin action
        await supabase.from('admin_actions').insert({
          admin_id: user?.id,
          action_type: 'confirm_subscription_payment',
          target_id: id,
          target_type: 'subscription',
          comment: comment,
          metadata: { confirmed_at: new Date().toISOString() }
        });
      } else {
        // Confirm order
        const { error } = await supabase
          .from('orders')
          .update({ status: 'paid' })
          .eq('id', id);

        if (error) throw error;

        // Log admin action
        await supabase.from('admin_actions').insert({
          admin_id: user?.id,
          action_type: 'confirm_order_payment',
          target_id: id,
          target_type: 'order',
          comment: comment,
          metadata: { confirmed_at: new Date().toISOString() }
        });
      }
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      queryClient.invalidateQueries({ queryKey: ['balance'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      queryClient.invalidateQueries({ queryKey: ['profile'] });
      
      toast.success(
        variables.type === 'subscription' 
          ? 'Подписка успешно подтверждена' 
          : 'Оплата заказа подтверждена'
      );
    },
    onError: (error) => {
      toast.error(`Ошибка подтверждения: ${error.message}`);
    }
  });
}
