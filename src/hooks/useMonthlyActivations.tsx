import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface ActivationReportItem {
  user_id: string;
  full_name: string;
  email: string;
  referral_code: string;
  total_amount_kzt: number;
  threshold_kzt: number;
  is_activated: boolean;
  last_order_date: string | null;
  orders_count: number;
  activation_due_from: string | null;
  admin_comment: string | null;
  // New personal period fields
  period_number: number | null;
  period_start: string | null;
  period_end: string | null;
}

export interface ActivationCounts {
  total: number;
  activated: number;
  not_activated: number;
  threshold_kzt: number;
}

export interface PartnerOrderItem {
  order_id: string;
  order_date: string;
  total_kzt: number;
  total_usd: number;
  status: string;
  items: Array<{
    product_id: string;
    title: string;
    qty: number;
    price_kzt: number;
    is_activation: boolean;
  }>;
}

interface UseMonthlyActivationsOptions {
  year: number;
  month: number;
  status?: 'all' | 'activated' | 'not_activated';
  search?: string;
  limit?: number;
  offset?: number;
}

export function useMonthlyActivationsReport(options: UseMonthlyActivationsOptions) {
  const { year, month, status = 'all', search = '', limit = 50, offset = 0 } = options;

  return useQuery({
    queryKey: ['monthly-activations-report', year, month, status, search, limit, offset],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_monthly_activation_report', {
        p_year: year,
        p_month: month,
        p_status: status,
        p_search: search || null,
        p_limit: limit,
        p_offset: offset
      });

      if (error) throw error;
      return (data || []) as ActivationReportItem[];
    },
    staleTime: 30000
  });
}

export function useMonthlyActivationsCounts(year: number, month: number, search?: string) {
  return useQuery({
    queryKey: ['monthly-activations-counts', year, month, search],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_monthly_activation_count', {
        p_year: year,
        p_month: month,
        p_status: 'all',
        p_search: search || null
      });

      if (error) throw error;
      return data as unknown as ActivationCounts;
    },
    staleTime: 30000
  });
}

export function usePartnerOrdersForMonth(userId: string | null, year: number, month: number) {
  return useQuery({
    queryKey: ['partner-orders-month', userId, year, month],
    queryFn: async () => {
      if (!userId) return [];
      
      const { data, error } = await supabase.rpc('get_partner_orders_for_month', {
        p_user_id: userId,
        p_year: year,
        p_month: month
      });

      if (error) throw error;
      return (data || []) as PartnerOrderItem[];
    },
    enabled: !!userId,
    staleTime: 30000
  });
}

export function useRecalculateMonthlyActivations() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: { year?: number; month?: number }) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('recalculate_monthly_activations', {
        p_admin_id: user.id,
        p_year: params.year || null,
        p_month: params.month || null
      });

      if (error) throw error;
      return data;
    },
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['monthly-activations-report'] });
      queryClient.invalidateQueries({ queryKey: ['monthly-activations-counts'] });
      toast.success(`Пересчёт завершён: создано ${data.created}, обновлено ${data.updated}`);
    },
    onError: (error) => {
      toast.error('Ошибка пересчёта: ' + error.message);
    }
  });
}

// Get current activation threshold from settings
export function useActivationThreshold() {
  return useQuery({
    queryKey: ['activation-threshold'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('shop_settings')
        .select('monthly_activation_required_kzt, monthly_activation_required_usd')
        .eq('id', 1)
        .single();

      if (error) throw error;
      return {
        kzt: Number(data?.monthly_activation_required_kzt) || 20000,
        usd: Number(data?.monthly_activation_required_usd) || 40
      };
    },
    staleTime: 60000
  });
}

// Update activation comment
export function useUpdateActivationComment() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: { userId: string; year: number; month: number; comment: string }) => {
      const { error } = await supabase
        .from('monthly_activations')
        .update({ 
          admin_comment: params.comment, 
          updated_at: new Date().toISOString() 
        })
        .eq('user_id', params.userId)
        .eq('year', params.year)
        .eq('month', params.month);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['monthly-activations-report'] });
      toast.success("Комментарий сохранён");
    },
    onError: (error) => {
      toast.error('Ошибка сохранения комментария: ' + error.message);
    }
  });
}

// Export all activations data (for full Excel export)
export function useExportAllActivations() {
  return useMutation({
    mutationFn: async (params: { 
      year: number; 
      month: number; 
      status?: 'all' | 'activated' | 'not_activated'; 
      search?: string 
    }) => {
      const { year, month, status = 'all', search = '' } = params;
      
      const { data, error } = await supabase.rpc('get_monthly_activation_report', {
        p_year: year,
        p_month: month,
        p_status: status,
        p_search: search || null,
        p_limit: 10000, // Large limit to get all data
        p_offset: 0
      });

      if (error) throw error;
      return (data || []) as ActivationReportItem[];
    }
  });
}
