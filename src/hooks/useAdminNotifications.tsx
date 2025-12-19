import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

export interface AdminNotification {
  id: string;
  admin_id: string;
  type: 'status_achievement' | 'payment' | 'system' | 'suspicious_activity' | 'commission' | 'payment_error';
  title: string;
  message: string;
  read: boolean;
  metadata: any;
  created_at: string;
}

export function useAdminNotifications() {
  const { user, userRole } = useAuth();

  return useQuery({
    queryKey: ['admin-notifications', user?.id],
    queryFn: async () => {
      if (!user || (userRole !== 'admin' && userRole !== 'superadmin')) {
        return [];
      }

      const { data, error } = await supabase
        .from('admin_notifications')
        .select('*')
        .eq('admin_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50);

      if (error) throw error;
      return (data || []) as AdminNotification[];
    },
    enabled: !!user && (userRole === 'admin' || userRole === 'superadmin')
  });
}

export async function markNotificationAsRead(notificationId: string) {
  const { error } = await supabase
    .from('admin_notifications')
    .update({ read: true })
    .eq('id', notificationId);

  if (error) throw error;
}
