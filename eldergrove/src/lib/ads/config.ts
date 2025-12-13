// Ad configuration constants
export const AD_SPEED_UP_MINUTES = 30; // Minutes reduced per ad watch
export const AD_HOURLY_LIMIT = 5; // Maximum ads per hour

// AdMob App IDs (set via environment variables)
export const ADMOB_APP_ID_IOS = process.env.NEXT_PUBLIC_ADMOB_APP_ID_IOS || '';
export const ADMOB_APP_ID_ANDROID = process.env.NEXT_PUBLIC_ADMOB_APP_ID_ANDROID || '';

// AdMob Ad Unit IDs (set via environment variables)
export const ADMOB_REWARDED_AD_UNIT_ID_IOS = process.env.NEXT_PUBLIC_ADMOB_REWARDED_AD_UNIT_ID_IOS || '';
export const ADMOB_REWARDED_AD_UNIT_ID_ANDROID = process.env.NEXT_PUBLIC_ADMOB_REWARDED_AD_UNIT_ID_ANDROID || '';

// Test ad unit IDs (for development)
export const ADMOB_TEST_REWARDED_AD_UNIT_ID = 'ca-app-pub-3940256099942544/5224354917';

// Google Ad Manager configuration for web
export const GAM_PUBLISHER_ID = process.env.NEXT_PUBLIC_GAM_PUBLISHER_ID || '';
export const GAM_REWARDED_AD_UNIT_ID = process.env.NEXT_PUBLIC_GAM_REWARDED_AD_UNIT_ID || '';

