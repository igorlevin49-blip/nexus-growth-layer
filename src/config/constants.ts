// Application constants
export const APP_CONFIG = {
  // Production domain - always use this instead of window.location.origin
  DOMAIN: 'https://mg-market.kz',
  APP_NAME: 'MG Market',
  
  // Referral system
  REFERRAL_COOKIE_KEY: 'mg_ref_code',
  REFERRAL_COOKIE_EXPIRY_DAYS: 30,
  
  // Structure types
  STRUCTURE_PRIMARY: 1, // Classic MLM structure
  STRUCTURE_SECONDARY: 2, // Product/activation-based structure
  
  // Network levels
  MAX_NETWORK_LEVELS: 10,
} as const;

export const getAppUrl = (path: string = '') => {
  return `${APP_CONFIG.DOMAIN}${path}`;
};

export const getReferralLink = (refCode: string) => {
  return `${APP_CONFIG.DOMAIN}/register?ref=${refCode}`;
};
