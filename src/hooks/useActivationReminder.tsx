import { useState, useEffect } from 'react';
import { useAuth } from './useAuth';
import { supabase } from '@/integrations/supabase/client';
import { differenceInDays, startOfDay } from 'date-fns';

export function useActivationReminder() {
  const { user } = useAuth();
  const [showReminder, setShowReminder] = useState(false);
  const [daysLeft, setDaysLeft] = useState<number | null>(null);
  const [activationDueFrom, setActivationDueFrom] = useState<Date | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) {
      setLoading(false);
      return;
    }

    const checkActivationReminder = async () => {
      try {
        const { data: profile, error } = await supabase
          .from('profiles')
          .select('activation_due_from, monthly_activation_completed, subscription_status')
          .eq('id', user.id)
          .single();

        if (error || !profile) {
          setLoading(false);
          return;
        }

        // Не показывать, если подписка неактивна
        if (profile.subscription_status !== 'active') {
          setLoading(false);
          return;
        }

        // Не показывать, если активация уже выполнена
        if (profile.monthly_activation_completed) {
          setLoading(false);
          return;
        }

        // Не показывать, если нет даты активации
        if (!profile.activation_due_from) {
          setLoading(false);
          return;
        }

        const dueDate = new Date(profile.activation_due_from);
        const today = startOfDay(new Date());
        const dueDateStart = startOfDay(dueDate);
        const days = differenceInDays(dueDateStart, today);

        // Показывать только если осталось 1-5 дней
        if (days < 1 || days > 5) {
          setLoading(false);
          return;
        }

        // Проверяем localStorage - показывали ли сегодня
        const storageKey = `activation_reminder_${user.id}`;
        const lastShown = localStorage.getItem(storageKey);
        const todayStr = today.toISOString().split('T')[0];

        if (lastShown === todayStr) {
          setLoading(false);
          return;
        }

        setDaysLeft(days);
        setActivationDueFrom(dueDate);
        setShowReminder(true);
        setLoading(false);
      } catch (err) {
        console.error('Error checking activation reminder:', err);
        setLoading(false);
      }
    };

    checkActivationReminder();
  }, [user]);

  const closeReminder = () => {
    if (user) {
      const storageKey = `activation_reminder_${user.id}`;
      const todayStr = startOfDay(new Date()).toISOString().split('T')[0];
      localStorage.setItem(storageKey, todayStr);
    }
    setShowReminder(false);
  };

  return {
    showReminder,
    daysLeft,
    activationDueFrom,
    closeReminder,
    loading
  };
}
