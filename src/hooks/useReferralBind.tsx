import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from './useAuth';
import { getReferralCode, clearReferralCode } from './useReferralCapture';
import { toast } from 'sonner';

/**
 * Auto-bind referral from storage on first login if not already set
 * Multiple attempts with improved error handling
 */
export function useReferralBind() {
  const { user } = useAuth();
  const [attemptCount, setAttemptCount] = useState(0);
  const maxAttempts = 3;

  useEffect(() => {
    if (!user || attemptCount >= maxAttempts) return;

    const attemptBind = async () => {
      try {
        // Check if user already has sponsor
        const { data: profile } = await supabase
          .from('profiles')
          .select('sponsor_id')
          .eq('id', user.id)
          .single();

        // If already has sponsor, clear referral code and stop
        if (profile?.sponsor_id) {
          clearReferralCode();
          return;
        }

        // Try to get referral code from any storage
        const refCode = getReferralCode();
        
        if (!refCode) {
          return; // No referral code found
        }

        console.log(`Attempting to bind referral (attempt ${attemptCount + 1}/${maxAttempts}):`, refCode);

        // Attempt to bind referral
        const { data, error } = await supabase.rpc('bind_referral', {
          p_ref_code: refCode.trim()
        });

        if (error) {
          console.error('Bind referral error:', error);
          
          // Retry on network errors
          if (error.message?.includes('network') || error.message?.includes('fetch')) {
            setAttemptCount(prev => prev + 1);
            return;
          }
          
          // Clear invalid referral codes
          if (error.message?.includes('invalid_code')) {
            clearReferralCode();
          }
          return;
        }

        const result = data as { success?: boolean; error?: string; sponsor_name?: string } | null;
        
        if (result?.success) {
          // Success - clear the referral code
          clearReferralCode();
          
          if (result.sponsor_name && result.error !== 'already_bound') {
            toast.success(`Вы привязаны к спонсору: ${result.sponsor_name}`);
          }
          
          console.log('Referral bound successfully:', result);
        } else {
          // Handle specific errors
          const errorCode = result?.error;
          
          if (errorCode === 'already_has_sponsor' || errorCode === 'already_bound') {
            clearReferralCode(); // Clear code if already bound
          } else if (errorCode === 'invalid_code') {
            clearReferralCode(); // Clear invalid code
            console.warn('Invalid referral code:', refCode);
          } else if (errorCode === 'self_referral') {
            clearReferralCode(); // Clear self-referral attempt
          } else if (errorCode === 'already_sponsor') {
            clearReferralCode(); // User is already a sponsor, cannot be bound
            console.warn('User is already a sponsor, cannot bind:', refCode);
          } else if (errorCode === 'sponsor_registered_later') {
            clearReferralCode(); // Sponsor registered after user
            console.warn('Sponsor registered later than user:', refCode);
          } else {
            // Retry on unknown errors
            setAttemptCount(prev => prev + 1);
          }
        }
      } catch (err) {
        console.error('Auto-bind referral failed:', err);
        setAttemptCount(prev => prev + 1);
      }
    };

    // Delay first attempt to ensure user session is fully established
    const timeout = setTimeout(() => {
      attemptBind();
    }, attemptCount === 0 ? 1000 : 3000 * attemptCount); // Exponential backoff

    return () => clearTimeout(timeout);
  }, [user, attemptCount]);
}
