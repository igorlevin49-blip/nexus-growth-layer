import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface CreateManualSubscriptionParams {
  amount_usd: number;
  amount_kzt: number;
}

interface CreateManualActivationParams {
  product_id: string;
}

interface ApprovePaymentParams {
  record_type: 'subscription' | 'order';
  record_id: string;
  comment: string;
  payment_proof_url?: string;
}

interface RejectPaymentParams {
  record_type: 'subscription' | 'order';
  record_id: string;
  comment: string;
}

export function useManualPayment() {
  const queryClient = useQueryClient();

  const createManualSubscription = useMutation({
    mutationFn: async ({ amount_usd, amount_kzt }: CreateManualSubscriptionParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('subscriptions')
        .insert([{
          user_id: user.id,
          amount_usd,
          amount_kzt,
          status: 'pending',
          payment_method: 'manual'
        }])
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      toast.success('Заявка на оплату подписки отправлена', {
        description: 'Администратор рассмотрит вашу заявку в ближайшее время'
      });
    },
    onError: (error: Error) => {
      toast.error('Ошибка при создании заявки', {
        description: error.message
      });
    }
  });

  const createManualActivation = useMutation({
    mutationFn: async ({ product_id }: CreateManualActivationParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Get product details
      const { data: product, error: productError } = await supabase
        .from('products')
        .select('*')
        .eq('id', product_id)
        .eq('is_activation', true)
        .single();

      if (productError) throw productError;
      if (!product) throw new Error('Activation product not found');

      // Create order
      const { data: order, error: orderError } = await supabase
        .from('orders')
        .insert([{
          user_id: user.id,
          status: 'pending',
          total_usd: product.price_usd,
          total_kzt: product.price_kzt
        }])
        .select()
        .single();

      if (orderError) throw orderError;

      // Add order item
      const { error: itemError } = await supabase
        .from('order_items')
        .insert([{
          order_id: order.id,
          product_id: product.id,
          qty: 1,
          price_usd: product.price_usd,
          price_kzt: product.price_kzt,
          is_activation_snapshot: true
        }]);

      if (itemError) throw itemError;

      return order;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      toast.success('Заявка на активацию отправлена', {
        description: 'Администратор рассмотрит вашу заявку в ближайшее время'
      });
    },
    onError: (error: Error) => {
      toast.error('Ошибка при создании заявки', {
        description: error.message
      });
    }
  });

  const approvePayment = useMutation({
    mutationFn: async ({ record_type, record_id, comment, payment_proof_url }: ApprovePaymentParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      if (record_type === 'subscription') {
        const { data, error } = await supabase.rpc('approve_subscription_payment', {
          p_subscription_id: record_id,
          p_admin_id: user.id,
          p_comment: comment,
          p_payment_proof_url: payment_proof_url || null
        });

        if (error) throw error;
        const result = data as any;
        if (!result?.success) throw new Error(result?.message || result?.error || 'Ошибка одобрения');
        return result;
      } else {
        const { data, error } = await supabase.rpc('approve_activation_order', {
          p_order_id: record_id,
          p_admin_id: user.id,
          p_comment: comment,
          p_payment_proof_url: payment_proof_url || null
        });

        if (error) throw error;
        const result = data as any;
        if (!result?.success) throw new Error(result?.message || result?.error || 'Ошибка одобрения');
        return result;
      }
    },
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      toast.success(data?.message || 'Платёж одобрен');
    },
    onError: (error: Error) => {
      toast.error('Ошибка при одобрении платежа', {
        description: error.message
      });
    }
  });

  const rejectPayment = useMutation({
    mutationFn: async ({ record_type, record_id, comment }: RejectPaymentParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('reject_payment', {
        p_record_type: record_type,
        p_record_id: record_id,
        p_admin_id: user.id,
        p_comment: comment
      });

      if (error) throw error;
      const result = data as any;
      if (!result?.success) throw new Error(result?.message || result?.error || 'Ошибка отклонения');
      return result;
    },
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      toast.success(data?.message || 'Платёж отклонён');
    },
    onError: (error: Error) => {
      toast.error('Ошибка при отклонении платежа', {
        description: error.message
      });
    }
  });

  return {
    createManualSubscription,
    createManualActivation,
    approvePayment,
    rejectPayment
  };
}
