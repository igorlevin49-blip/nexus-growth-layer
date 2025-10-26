import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export interface MLMCommissionRule {
  id: string;
  structure_type: 1 | 2; // 1 = абонентская, 2 = товарная
  level: number;
  percent: number;
  plan_id: string;
  effective_from: string;
}

export interface CommissionLevel extends MLMCommissionRule {
  partners_count?: number; // количество партнёров на уровне
  volume?: number; // объем продаж/подписок
  earned?: number; // заработано
  frozen?: number; // заморожено
  status?: 'active' | 'frozen' | 'locked'; // статус уровня
  unlock_requirement?: number; // сколько нужно прямых рефералов для разблокировки
}

interface UseCommissionStructureOptions {
  structureType?: 1 | 2; // 1 = абонентская (5 уровней), 2 = товарная (10 уровней)
  startDate?: Date;
  endDate?: Date;
}

export function useCommissionStructure(options: UseCommissionStructureOptions = {}) {
  const { structureType = 1, startDate, endDate } = options;

  return useQuery({
    queryKey: ['commission-structure', structureType, startDate, endDate],
    queryFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Получить правила комиссий из новой таблицы mlm_commission_rules
      const { data: rules, error: rulesError } = await supabase
        .from('mlm_commission_rules')
        .select('*')
        .eq('structure_type', structureType)
        .eq('plan_id', 'default')
        .order('level', { ascending: true });

      if (rulesError) throw rulesError;

      // Получить профиль текущего пользователя для проверки статуса подписки
      const { data: profile } = await supabase
        .from('profiles')
        .select('subscription_status, subscription_expires_at, monthly_activation_completed')
        .eq('id', user.id)
        .single();

      // Подсчитать прямых рефералов
      const { count: directReferralsCount } = await supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true })
        .eq('sponsor_id', user.id);

      // Условия разблокировки уровней (для структуры 1)
      const unlockRequirements: Record<number, number> = {
        1: 0,  // L1 всегда открыт
        2: 3,  // L2 при 3 приглашённых
        3: 5,  // L3 при 5 приглашённых
        4: 8,  // L4 при 8 приглашённых
        5: 10  // L5 при 10 приглашённых
      };

      const directReferrals = directReferralsCount || 0;
      const isSubscriptionActive = profile?.subscription_status === 'active';
      const isMonthlyActivationMet = profile?.monthly_activation_completed || false;

      // Обогащение данных для каждого уровня
      const enrichedLevels = await Promise.all(
        (rules || []).map(async (rule) => {
          // Определить статус уровня
          let status: 'active' | 'frozen' | 'locked' = 'locked';
          
          if (structureType === 1) {
            // Структура 1: проверка количества прямых рефералов и статуса подписки
            const unlockReq = unlockRequirements[rule.level] || 999;
            if (directReferrals >= unlockReq) {
              status = isSubscriptionActive ? 'active' : 'frozen';
            }
          } else {
            // Структура 2: проверка активной подписки + месячной активации
            if (isSubscriptionActive && isMonthlyActivationMet) {
              status = 'active';
            } else if (isSubscriptionActive) {
              status = 'frozen'; // подписка есть, но нет активации
            }
          }

          // Получить транзакции для этого уровня
          let transQuery = supabase
            .from('transactions')
            .select('amount_cents, status, frozen_until')
            .eq('user_id', user.id)
            .eq('level', rule.level)
            .eq('type', 'commission');

          // Фильтр по типу структуры через payload или другое поле
          // (предполагаем, что в transactions есть поле для различения структур)

          if (startDate) {
            transQuery = transQuery.gte('created_at', startDate.toISOString());
          }
          if (endDate) {
            transQuery = transQuery.lte('created_at', endDate.toISOString());
          }

          const { data: trans } = await transQuery;
          
          const earned = (trans || [])
            .filter(t => t.status === 'completed' && (!t.frozen_until || new Date(t.frozen_until) <= new Date()))
            .reduce((sum, t) => sum + (t.amount_cents || 0), 0);
          
          const frozen = (trans || [])
            .filter(t => t.status === 'completed' && t.frozen_until && new Date(t.frozen_until) > new Date())
            .reduce((sum, t) => sum + (t.amount_cents || 0), 0);

          const volume = earned > 0 ? Math.round(earned / (rule.percent / 100)) : 0;

          // Подсчет партнеров на уровне (можно получить из referrals или профилей)
          const { count: partnersCount } = await supabase
            .from('referrals')
            .select('*', { count: 'exact', head: true })
            .eq('referrer_id', user.id)
            .eq('structure_type', structureType);

          return {
            ...rule,
            partners_count: partnersCount || 0,
            volume,
            earned,
            frozen,
            status,
            unlock_requirement: structureType === 1 ? unlockRequirements[rule.level] : undefined
          } as CommissionLevel;
        })
      );

      return enrichedLevels;
    }
  });
}
