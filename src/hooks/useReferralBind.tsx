import { useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from './useAuth';
import { getCookie, deleteCookie } from '@/utils/cookies';
import { APP_CONFIG } from '@/config/constants';

/**
 * Auto-bind referral from cookie on first login if not already set
 */
export function useReferralBind() {
  const { user } = useAuth();

  useEffect(() => {
    if (!user) return;

    const refCode = getCookie(APP_CONFIG.REFERRAL_COOKIE_KEY);
    if (!refCode) return;

    // Attempt to bind referral (idempotent)
    (async () => {
      try {
        const { data } = await supabase.rpc('bind_referral', {
          p_ref_code: refCode.trim()
        });

        const result = data as { success?: boolean; error?: string } | null;
        if (result?.success) {
          // Clear cookie after successful bind
          deleteCookie(APP_CONFIG.REFERRAL_COOKIE_KEY);
        }
      } catch (err) {
        console.error('Auto-bind referral failed:', err);
      }
    })();
  }, [user]);
}
