import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { setCookie, getCookie } from '@/utils/cookies';
import { APP_CONFIG } from '@/config/constants';

const REFERRAL_STORAGE_KEY = 'mlm_referral_code';

/**
 * Captures referral code from URL and stores it in both cookie and localStorage
 * Uses multiple storage methods for reliability
 */
export function useReferralCapture() {
  const location = useLocation();

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const refCode = params.get('ref');
    
    if (refCode && refCode.trim()) {
      const cleanCode = refCode.trim();
      
      // Store in cookie (primary method)
      try {
        setCookie(APP_CONFIG.REFERRAL_COOKIE_KEY, cleanCode, APP_CONFIG.REFERRAL_COOKIE_EXPIRY_DAYS);
      } catch (error) {
        console.warn('Failed to set referral cookie:', error);
      }
      
      // Store in localStorage as fallback
      try {
        localStorage.setItem(REFERRAL_STORAGE_KEY, cleanCode);
        localStorage.setItem(`${REFERRAL_STORAGE_KEY}_timestamp`, Date.now().toString());
      } catch (error) {
        console.warn('Failed to set referral localStorage:', error);
      }
      
      // Store in sessionStorage as additional fallback
      try {
        sessionStorage.setItem(REFERRAL_STORAGE_KEY, cleanCode);
      } catch (error) {
        console.warn('Failed to set referral sessionStorage:', error);
      }

      console.log('Referral code captured:', cleanCode);
    }
  }, [location.search]);
}

/**
 * Retrieves referral code from any available storage
 * Checks cookie, localStorage, and sessionStorage in order
 */
export function getReferralCode(): string | null {
  // Try cookie first
  const fromCookie = getCookie(APP_CONFIG.REFERRAL_COOKIE_KEY);
  if (fromCookie) return fromCookie;
  
  // Try localStorage
  try {
    const fromLocalStorage = localStorage.getItem(REFERRAL_STORAGE_KEY);
    if (fromLocalStorage) {
      // Check if not too old (max 30 days)
      const timestamp = localStorage.getItem(`${REFERRAL_STORAGE_KEY}_timestamp`);
      if (timestamp) {
        const age = Date.now() - parseInt(timestamp);
        const maxAge = 30 * 24 * 60 * 60 * 1000; // 30 days
        if (age < maxAge) {
          return fromLocalStorage;
        }
      }
    }
  } catch (error) {
    console.warn('Failed to read from localStorage:', error);
  }
  
  // Try sessionStorage
  try {
    const fromSessionStorage = sessionStorage.getItem(REFERRAL_STORAGE_KEY);
    if (fromSessionStorage) return fromSessionStorage;
  } catch (error) {
    console.warn('Failed to read from sessionStorage:', error);
  }
  
  return null;
}

/**
 * Clears referral code from all storage locations
 */
export function clearReferralCode(): void {
  // Clear from cookie
  try {
    const expires = new Date(0).toUTCString();
    document.cookie = `${APP_CONFIG.REFERRAL_COOKIE_KEY}=; expires=${expires}; path=/`;
  } catch (error) {
    console.warn('Failed to clear referral cookie:', error);
  }
  
  // Clear from localStorage
  try {
    localStorage.removeItem(REFERRAL_STORAGE_KEY);
    localStorage.removeItem(`${REFERRAL_STORAGE_KEY}_timestamp`);
  } catch (error) {
    console.warn('Failed to clear referral localStorage:', error);
  }
  
  // Clear from sessionStorage
  try {
    sessionStorage.removeItem(REFERRAL_STORAGE_KEY);
  } catch (error) {
    console.warn('Failed to clear referral sessionStorage:', error);
  }
}
