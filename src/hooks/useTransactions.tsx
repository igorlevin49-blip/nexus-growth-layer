import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface Transaction {
  id: string;
  user_id: string;
  type: 'commission' | 'bonus' | 'withdrawal' | 'adjustment' | 'purchase';
  amount_kzt: number;
  currency: string;
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'frozen';
  source_id: string | null;
  source_ref: string | null;
  level: number | null;
  structure_type: 'primary' | 'secondary';
  payload: any;
  frozen_until: string | null;
  created_at: string;
  updated_at: string;
  source_user_name?: string; // ФИО пользователя-источника комиссии
}

type TransactionType = 'commission' | 'bonus' | 'withdrawal' | 'adjustment' | 'purchase';

interface UseTransactionsOptions {
  type?: TransactionType[];
  startDate?: Date;
  endDate?: Date;
  limit?: number;
  offset?: number;
}

export function useTransactions(options: UseTransactionsOptions = {}) {
  const { type, startDate, endDate, limit = 50, offset = 0 } = options;

  return useQuery({
    queryKey: ['transactions', type, startDate, endDate, limit, offset],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      let query = supabase
        .from('transactions')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .range(offset, offset + limit - 1);

      if (type && type.length > 0) {
        query = query.in('type', type);
      }

      if (startDate) {
        query = query.gte('created_at', startDate.toISOString());
      }

      if (endDate) {
        query = query.lte('created_at', endDate.toISOString());
      }

      const { data, error } = await query;

      if (error) throw error;
      
      // Map from DB column names (amount_cents in types.ts until regenerated) to our interface
      const transactions = (data || []).map((t: any) => ({
        ...t,
        amount_kzt: t.amount_kzt ?? t.amount_cents ?? 0
      })) as Transaction[];
      
      // Получаем уникальные source_user_id из payload для подтягивания ФИО
      const sourceUserIds = transactions
        .filter(t => t.payload?.source_user_id)
        .map(t => t.payload.source_user_id as string);
      
      const uniqueSourceUserIds = [...new Set(sourceUserIds)];
      
      if (uniqueSourceUserIds.length > 0) {
        const { data: profiles } = await supabase
          .from('profiles')
          .select('id, full_name')
          .in('id', uniqueSourceUserIds);
        
        if (profiles) {
          const profileMap = new Map(profiles.map(p => [p.id, p.full_name]));
          transactions.forEach(t => {
            if (t.payload?.source_user_id) {
              t.source_user_name = profileMap.get(t.payload.source_user_id) || undefined;
            }
          });
        }
      }
      
      return transactions;
    }
  });
}
