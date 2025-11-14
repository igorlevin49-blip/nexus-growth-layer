import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface MLMSetting {
  key: string;
  value: any;
  description?: string;
  updated_at?: string;
}

export function useMLMSettings() {
  return useQuery({
    queryKey: ['mlm-settings'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('mlm_settings')
        .select('*')
        .order('key');

      if (error) throw error;
      
      // Преобразовать в объект для удобства
      const settings: Record<string, any> = {};
      (data || []).forEach(item => {
        settings[item.key] = item.value;
      });
      
      return settings;
    }
  });
}

export function useUpdateMLMSetting() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ key, value }: { key: string; value: any }) => {
      const { error } = await supabase
        .from('mlm_settings')
        .upsert({ key, value }, { onConflict: 'key' });

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mlm-settings'] });
      toast.success('Настройка обновлена');
    },
    onError: (error) => {
      toast.error(`Ошибка: ${error.message}`);
    }
  });
}

/**
 * MLM Settings and Rules Management
 * 
 * ВАЖНО: Проценты комиссий - единый источник правды в mlm_commission_rules.
 * 
 * Абонентская структура (structure_type = 1):
 * - 5 уровней, каждый получает 10% от стоимости подписки
 * - Изменения процентов должны производиться ТОЛЬКО через эту таблицу
 * 
 * Товарная структура (structure_type = 2):
 * - Проценты также управляются через mlm_commission_rules
 */

export function useUpdateMLMRule() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (rule: {
      id?: string;
      structure_type: number;
      level: number;
      percent: number;
      plan_id?: string;
      is_active?: boolean;
    }) => {
      if (rule.id) {
        const { error } = await supabase
          .from('mlm_commission_rules')
          .update({
            percent: rule.percent,
            is_active: rule.is_active ?? true
          })
          .eq('id', rule.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('mlm_commission_rules')
          .insert({
            structure_type: rule.structure_type,
            level: rule.level,
            percent: rule.percent,
            plan_id: rule.plan_id || 'default',
            is_active: rule.is_active ?? true
          });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mlm-rules'] });
      toast.success('Правило обновлено');
    },
    onError: (error) => {
      toast.error(`Ошибка: ${error.message}`);
    }
  });
}