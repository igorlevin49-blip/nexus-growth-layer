import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "./useAuth";

export interface NotificationSettings {
  id: string;
  user_id: string;
  email_new_partner: boolean;
  email_commissions: boolean;
  email_system: boolean;
  email_newsletter: boolean;
  sms_enabled: boolean;
  telegram_enabled: boolean;
}

const defaultSettings: Omit<NotificationSettings, 'id' | 'user_id'> = {
  email_new_partner: true,
  email_commissions: true,
  email_system: false,
  email_newsletter: false,
  sms_enabled: false,
  telegram_enabled: true
};

export function useNotificationSettings() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['notification-settings', user?.id],
    queryFn: async () => {
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('notification_settings')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();

      if (error && error.code !== 'PGRST116') throw error;

      // Create default settings if none exist
      if (!data) {
        const { data: newData, error: insertError } = await supabase
          .from('notification_settings')
          .insert([{ user_id: user.id, ...defaultSettings }])
          .select()
          .single();

        if (insertError) throw insertError;
        return newData as NotificationSettings;
      }

      return data as NotificationSettings;
    },
    enabled: !!user
  });

  const updateSettings = useMutation({
    mutationFn: async (updates: Partial<Omit<NotificationSettings, 'id' | 'user_id'>>) => {
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('notification_settings')
        .update(updates)
        .eq('user_id', user.id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notification-settings', user?.id] });
    },
    onError: (error: Error) => {
      toast.error('Ошибка при обновлении настроек');
      console.error(error);
    }
  });

  return {
    ...query,
    updateSettings
  };
}
