import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

// SECURITY: meta field should ONLY contain tokenized payment data
// NEVER store: full card numbers, CVV, passwords, or sensitive credentials
// ALLOWED: token_id, last4, provider_id, payment_method_id from payment provider
export interface PaymentMethodMeta {
  token_id?: string;        // Payment provider token ID
  last4?: string;           // Last 4 digits only
  provider_id?: string;     // Payment provider identifier
  payment_method_id?: string; // External payment method reference
  [key: string]: string | undefined; // Allow other non-sensitive metadata
}

export interface PaymentMethod {
  id: string;
  user_id: string;
  type: 'card' | 'bank' | 'crypto' | 'other';
  masked: string;
  meta: PaymentMethodMeta;
  is_default: boolean;
  created_at: string;
  updated_at: string;
}

export function usePaymentMethods() {
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['payment-methods'],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('payment_methods')
        .select('*')
        .eq('user_id', user.id)
        .order('is_default', { ascending: false })
        .order('created_at', { ascending: false });

      if (error) throw error;
      return (data || []) as PaymentMethod[];
    }
  });

  // SECURITY: Validate payment method data before storing
  const validatePaymentMeta = (meta: PaymentMethodMeta): void => {
    const metaString = JSON.stringify(meta);
    
    // Check for suspicious patterns that might indicate sensitive data
    const suspiciousPatterns = [
      /\b\d{13,19}\b/,           // 13-19 digit sequences (card numbers)
      /\bcvv\b/i,                // CVV mentions
      /\bcvc\b/i,                // CVC mentions  
      /\bpassword\b/i,           // Password mentions
      /\bpin\b/i,                // PIN mentions
      /\d{3,4}$/,                // 3-4 digits at end (CVV pattern)
    ];
    
    for (const pattern of suspiciousPatterns) {
      if (pattern.test(metaString)) {
        throw new Error('Недопустимые данные: meta поле не должно содержать номера карт, CVV или пароли');
      }
    }
  };

  const addMethod = useMutation({
    mutationFn: async (method: Omit<PaymentMethod, 'id' | 'user_id' | 'created_at' | 'updated_at'>) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // SECURITY: Validate meta field before storing
      validatePaymentMeta(method.meta);

      const { data, error } = await supabase
        .from('payment_methods')
        .insert([{ ...method, user_id: user.id }])
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payment-methods'] });
      toast.success('Способ оплаты добавлен');
    },
    onError: () => {
      toast.error('Ошибка при добавлении способа оплаты');
    }
  });

  const removeMethod = useMutation({
    mutationFn: async (methodId: string) => {
      const { error } = await supabase
        .from('payment_methods')
        .delete()
        .eq('id', methodId);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payment-methods'] });
      toast.success('Способ оплаты удален');
    },
    onError: () => {
      toast.error('Ошибка при удалении способа оплаты');
    }
  });

  const setDefault = useMutation({
    mutationFn: async (methodId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Remove default from all methods
      await supabase
        .from('payment_methods')
        .update({ is_default: false })
        .eq('user_id', user.id);

      // Set new default
      const { error } = await supabase
        .from('payment_methods')
        .update({ is_default: true })
        .eq('id', methodId);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payment-methods'] });
      toast.success('Способ оплаты по умолчанию обновлен');
    },
    onError: () => {
      toast.error('Ошибка при обновлении способа оплаты');
    }
  });

  return {
    ...query,
    addMethod,
    removeMethod,
    setDefault
  };
}
