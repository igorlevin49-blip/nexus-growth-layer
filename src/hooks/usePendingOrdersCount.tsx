import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";

export function usePendingOrdersCount() {
  const { userRole } = useAuth();
  const queryClient = useQueryClient();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const notificationPermissionRef = useRef<NotificationPermission>('default');

  const isAdmin = userRole === 'admin' || userRole === 'superadmin';

  // Initialize audio and request notification permission
  useEffect(() => {
    if (!isAdmin || typeof window === 'undefined') return;

    // Initialize audio
    audioRef.current = new Audio('/sounds/new-order.mp3');
    audioRef.current.volume = 0.5;

    // Request notification permission
    if ('Notification' in window) {
      notificationPermissionRef.current = Notification.permission;
      
      if (Notification.permission === 'default') {
        Notification.requestPermission().then(permission => {
          notificationPermissionRef.current = permission;
        });
      }
    }

    return () => {
      audioRef.current = null;
    };
  }, [isAdmin]);

  // Play notification sound
  const playNotificationSound = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch(err => {
        console.log('Audio play failed:', err);
      });
    }
  }, []);

  // Show desktop notification
  const showDesktopNotification = useCallback((orderId: string) => {
    if (!('Notification' in window)) return;
    
    if (Notification.permission === 'granted') {
      const notification = new Notification('Новый заказ!', {
        body: 'Получен новый заказ на обработку',
        icon: '/favicon.ico',
        tag: `order-${orderId}`,
        requireInteraction: true,
      });

      notification.onclick = () => {
        window.focus();
        window.location.href = '/admin/orders';
        notification.close();
      };

      // Auto close after 10 seconds
      setTimeout(() => notification.close(), 10000);
    }
  }, []);

  // Realtime subscription
  useEffect(() => {
    if (!isAdmin) return;

    const channel = supabase
      .channel('orders-realtime')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'orders'
        },
        (payload) => {
          // Invalidate cache to get updated count
          queryClient.invalidateQueries({ queryKey: ['pending-orders-count'] });
          
          // If this is a new pending order - play sound, show toast and desktop notification
          if (payload.eventType === 'INSERT') {
            const newOrder = payload.new as { id?: string; status?: string; is_archived?: boolean };
            if (newOrder.status === 'pending' && !newOrder.is_archived) {
              playNotificationSound();
              
              // Show desktop notification
              if (newOrder.id) {
                showDesktopNotification(newOrder.id);
              }
              
              // Show toast notification
              toast.info("Новый заказ!", {
                description: "Получен новый заказ на обработку",
                action: {
                  label: "Открыть",
                  onClick: () => window.location.href = '/admin/orders'
                }
              });
            }
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [isAdmin, queryClient, playNotificationSound, showDesktopNotification]);

  return useQuery({
    queryKey: ['pending-orders-count'],
    queryFn: async () => {
      const { count, error } = await supabase
        .from('orders')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending')
        .or('is_archived.is.null,is_archived.eq.false');

      if (error) throw error;
      return count || 0;
    },
    enabled: isAdmin,
    refetchInterval: 60000,
  });
}
