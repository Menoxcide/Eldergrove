import { ADMOB_APP_ID_IOS, ADMOB_APP_ID_ANDROID, ADMOB_REWARDED_AD_UNIT_ID_IOS, ADMOB_REWARDED_AD_UNIT_ID_ANDROID, ADMOB_TEST_REWARDED_AD_UNIT_ID } from './config';

let adInitialized = false;
let rewardedAdLoaded = false;
let Capacitor: { getPlatform: () => string; isNativePlatform: () => boolean } | null = null;
let AdMob: {
  start: () => Promise<void>;
  prepareRewardVideoAd: (options: { adId: string; isTesting: boolean }) => Promise<void>;
  showRewardVideoAd: () => Promise<void>;
  addListener: (event: string, callback: (reward: { type: string; amount: number; adUnitId: string }) => void) => { remove: () => void };
} | null = null;

export function isMobile(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }
  
  if (typeof (window as typeof window & { Capacitor?: { isNativePlatform: () => boolean } }).Capacitor !== 'undefined') {
    return (window as typeof window & { Capacitor: { isNativePlatform: () => boolean } }).Capacitor.isNativePlatform();
  }
  
  return false;
}

async function loadCapacitorModules(): Promise<void> {
  if (Capacitor && AdMob) {
    return;
  }

  if (typeof window === 'undefined') {
    return;
  }

  try {
    const capacitorCoreModule = '@capacitor/core';
    const capacitorAdmobModule = '@capgo/capacitor-admob';
    
    const capacitorCore = await import(capacitorCoreModule);
    Capacitor = capacitorCore.Capacitor as typeof Capacitor;
    
    const capacitorAdmob = await import(capacitorAdmobModule);
    AdMob = capacitorAdmob.AdMob as typeof AdMob;
  } catch (error) {
    Capacitor = null;
    AdMob = null;
  }
}

export async function initializeAds(): Promise<void> {
  if (adInitialized) {
    return;
  }

  if (isMobile()) {
    try {
      await loadCapacitorModules();
      
      if (!Capacitor || !AdMob) {
        throw new Error('Capacitor modules not available');
      }

      const platform = Capacitor.getPlatform();
      const appId = platform === 'ios' ? ADMOB_APP_ID_IOS : ADMOB_APP_ID_ANDROID;
      
      if (!appId) {
        console.warn('AdMob App ID not configured. Using test ad unit.');
      }

      await AdMob.start();
      adInitialized = true;
      console.log('AdMob initialized');
    } catch (error) {
      console.error('Failed to initialize AdMob:', error);
      adInitialized = true;
    }
  } else {
    adInitialized = true;
    console.log('Using web ad fallback (mock ads)');
  }
}

export async function loadRewardedAd(): Promise<void> {
  if (!isMobile()) {
    rewardedAdLoaded = true;
    return;
  }

  try {
    if (!adInitialized) {
      await initializeAds();
    }

    await loadCapacitorModules();
    
    if (!Capacitor || !AdMob) {
      throw new Error('Capacitor modules not available');
    }

    const platform = Capacitor.getPlatform();
    const adUnitId = platform === 'ios' 
      ? (ADMOB_REWARDED_AD_UNIT_ID_IOS || ADMOB_TEST_REWARDED_AD_UNIT_ID)
      : (ADMOB_REWARDED_AD_UNIT_ID_ANDROID || ADMOB_TEST_REWARDED_AD_UNIT_ID);

    await AdMob.prepareRewardVideoAd({
      adId: adUnitId,
      isTesting: !adUnitId.includes('ca-app-pub-') || adUnitId === ADMOB_TEST_REWARDED_AD_UNIT_ID
    });
    rewardedAdLoaded = true;
    console.log('Rewarded ad loaded');
  } catch (error) {
    console.error('Failed to load rewarded ad:', error);
    throw error;
  }
}

export async function showRewardedAd(): Promise<void> {
  if (!isMobile()) {
    return new Promise((resolve) => {
      const duration = 3000 + Math.random() * 2000;
      setTimeout(() => {
        console.log('Mock ad completed');
        resolve();
      }, duration);
    });
  }

  try {
    if (!rewardedAdLoaded) {
      await loadRewardedAd();
    }

    await loadCapacitorModules();
    
    if (!Capacitor || !AdMob) {
      throw new Error('Capacitor modules not available');
    }

    const platform = Capacitor.getPlatform();
    const adUnitId = platform === 'ios' 
      ? (ADMOB_REWARDED_AD_UNIT_ID_IOS || ADMOB_TEST_REWARDED_AD_UNIT_ID)
      : (ADMOB_REWARDED_AD_UNIT_ID_ANDROID || ADMOB_TEST_REWARDED_AD_UNIT_ID);

    return new Promise<void>((resolve, reject) => {
      if (!AdMob) {
        throw new Error('AdMob not available');
      }

      const rewardListener = AdMob.addListener('onRewarded', (reward: { type: string; amount: number; adUnitId: string }) => {
        console.log('Ad reward granted:', reward);
        rewardListener.remove();
        resolve();
      });

      AdMob.showRewardVideoAd()
        .then(() => {
        })
        .catch((error: unknown) => {
          rewardListener.remove();
          reject(error);
        });
    });
  } catch (error) {
    console.error('Failed to show rewarded ad:', error);
    throw error;
  }
}

