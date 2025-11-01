import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "./useAuth";

export interface Profile {
  id: string;
  first_name: string | null;
  last_name: string | null;
  full_name: string | null;
  email: string | null;
  phone: string | null;
  telegram_username: string | null;
  avatar_url: string | null;
  language: 'ru' | 'kz' | 'en';
  timezone: string;
  is_public_profile: boolean;
  show_stats: boolean;
  allow_contacts: boolean;
  bio: string | null;
  subscription_status?: string;
  subscription_expires_at?: string | null;
  monthly_activation_completed?: boolean;
  sponsor_id?: string | null;
  referrer_snapshot?: any;
}

export function useProfile() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const query = useQuery({
    queryKey: ['profile', user?.id],
    queryFn: async () => {
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .single();

      if (error) throw error;
      return data as Profile;
    },
    enabled: !!user
  });

  const updateProfile = useMutation({
    mutationFn: async (updates: Partial<Profile>) => {
      if (!user) throw new Error('Not authenticated');

      // Validate phone if provided
      if (updates.phone) {
        const phoneRegex = /^\+?[1-9]\d{1,14}$/;
        if (!phoneRegex.test(updates.phone.replace(/[\s()-]/g, ''))) {
          throw new Error('Неверный формат телефона');
        }
        updates.phone = updates.phone.replace(/[\s()-]/g, '');
      }

      // Validate telegram username if provided
      if (updates.telegram_username) {
        const telegramRegex = /^[a-zA-Z0-9_]{5,32}$/;
        const username = updates.telegram_username.replace('@', '');
        if (!telegramRegex.test(username)) {
          throw new Error('Неверный формат Telegram username');
        }
        updates.telegram_username = username;
      }

      // Validate names
      if (updates.first_name && (updates.first_name.length < 1 || updates.first_name.length > 64)) {
        throw new Error('Имя должно быть от 1 до 64 символов');
      }
      if (updates.last_name && (updates.last_name.length < 1 || updates.last_name.length > 64)) {
        throw new Error('Фамилия должна быть от 1 до 64 символов');
      }

      const { data, error } = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', user.id)
        .select()
        .single();

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['profile', user?.id] });
      toast.success('Профиль обновлён');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Ошибка при обновлении профиля');
    }
  });

  return {
    ...query,
    updateProfile
  };
}
