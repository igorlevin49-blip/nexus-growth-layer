import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { setCookie } from '@/utils/cookies';
import { APP_CONFIG } from '@/config/constants';

/**
 * Capture ?ref=CODE from any route and persist to cookie
 * Ensures referral binding works even if user lands on non-register pages
 */
export function useReferralCapture() {
  const location = useLocation();

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const ref = params.get('ref');
    if (ref && ref.trim()) {
      setCookie(APP_CONFIG.REFERRAL_COOKIE_KEY, ref.trim(), APP_CONFIG.REFERRAL_COOKIE_EXPIRY_DAYS);
    }
  }, [location.search]);
}
