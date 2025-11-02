import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

export function SubscriptionStatus() {
  const { user } = useAuth();
  const [subscriptionStatus, setSubscriptionStatus] = useState<string>('inactive');
  const [expiresAt, setExpiresAt] = useState<Date | null>(null);

  useEffect(() => {
    if (user) {
      fetchSubscriptionStatus();

      // Subscribe to real-time updates
      const channel = supabase
        .channel('subscription-updates')
        .on(
          'postgres_changes',
          {
            event: '*',
            schema: 'public',
            table: 'profiles',
            filter: `id=eq.${user.id}`
          },
          (payload) => {
            if (payload.new && typeof payload.new === 'object' && 'subscription_status' in payload.new) {
              const newProfile = payload.new as any;
              setSubscriptionStatus(newProfile.subscription_status || 'inactive');
              if (newProfile.subscription_expires_at) {
                setExpiresAt(new Date(newProfile.subscription_expires_at));
              } else {
                setExpiresAt(null);
              }
            }
          }
        )
        .subscribe();

      return () => {
        supabase.removeChannel(channel);
      };
    }
  }, [user]);

  const fetchSubscriptionStatus = async () => {
    if (!user) return;

    try {
      const { data: profile, error } = await supabase
        .from('profiles')
        .select('subscription_status, subscription_expires_at')
        .eq('id', user.id)
        .single();

      if (error) throw error;

      if (profile) {
        setSubscriptionStatus(profile.subscription_status || 'inactive');
        if (profile.subscription_expires_at) {
          setExpiresAt(new Date(profile.subscription_expires_at));
        }
      }
    } catch (error) {
      console.error('Error fetching subscription status:', error);
    }
  };

  const isActive = subscriptionStatus === 'active';

  return (
    <div className="flex items-center space-x-4">
      <div className="hidden sm:block">
        <div className="flex items-center space-x-2 text-sm">
          <div className={`w-2 h-2 rounded-full ${isActive ? 'bg-success' : 'bg-warning'}`}></div>
          <span className="text-muted-foreground">
            {isActive && expiresAt
              ? `Подписка активна до ${format(expiresAt, 'dd.MM.yyyy', { locale: ru })}`
              : 'Подписка неактивна'}
          </span>
        </div>
      </div>
    </div>
  );
}
