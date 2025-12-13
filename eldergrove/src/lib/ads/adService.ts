import { ADMOB_APP_ID_IOS, ADMOB_APP_ID_ANDROID, ADMOB_REWARDED_AD_UNIT_ID_IOS, ADMOB_REWARDED_AD_UNIT_ID_ANDROID, ADMOB_TEST_REWARDED_AD_UNIT_ID, GAM_PUBLISHER_ID, GAM_REWARDED_AD_UNIT_ID } from './config';
import { handleError } from '@/hooks/useErrorHandler';

let adInitialized = false;
let rewardedAdLoaded = false;

// Default ad duration in milliseconds (30 seconds)
const DEFAULT_AD_DURATION = 30000;
let Capacitor: { getPlatform: () => string; isNativePlatform: () => boolean } | null = null;
let AdMob: {
  start: () => Promise<void>;
  prepareRewardVideoAd: (options: { adId: string; isTesting: boolean }) => Promise<void>;
  showRewardVideoAd: () => Promise<void>;
  addListener: (event: string, callback: (reward: { type: string; amount: number; adUnitId: string }) => void) => { remove: () => void };
} | null = null;

// Google Ad Manager types for web
declare global {
  interface Window {
    googletag?: {
      cmd: Array<() => void>;
      pubads: () => {
        addEventListener: (event: string, callback: () => void) => void;
        removeEventListener: (event: string, callback: () => void) => void;
      };
      defineSlot: (adUnitPath: string, size: number[], divId: string) => any;
      enableServices: () => void;
      display: (divId: string) => void;
    };
    google?: {
      ima?: {
        AdsManager: new (adDisplayContainer: any, videoElement: HTMLVideoElement) => any;
        AdDisplayContainer: new (container: HTMLElement, videoElement: HTMLVideoElement) => any;
        AdsLoader: new (adDisplayContainer: any) => any;
        AdsRequest: new () => any;
        ViewMode: {
          NORMAL: string;
        };
        AdEvent: {
          Type: {
            STARTED: string;
            COMPLETE: string;
            ERROR: string;
          };
        };
        AdsManagerLoadedEvent: {
          Type: {
            ADS_MANAGER_LOADED: string;
          };
        };
        AdsLoaderEvent: {
          Type: {
            ADS_LOADER_FAILED: string;
          };
        };
      };
    };
  }
}

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
  } catch {
    Capacitor = null;
    AdMob = null;
  }
}

async function loadGoogleAdManagerScript(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (typeof window === 'undefined') {
      reject(new Error('Window not available'));
      return;
    }

    // Check if already loaded
    if (window.googletag) {
      resolve();
      return;
    }

    // Load Google Publisher Tag
    const script = document.createElement('script');
    script.src = 'https://www.googletagservices.com/tag/js/gpt.js';
    script.async = true;
    script.onload = () => {
      if (window.googletag) {
        window.googletag.cmd = window.googletag.cmd || [];
        window.googletag.cmd.push(() => {
          window.googletag!.pubads().addEventListener('slotRenderEnded', () => {
            // Ad rendered
          });
        });
        resolve();
      } else {
        reject(new Error('Google Ad Manager failed to load'));
      }
    };
    script.onerror = () => reject(new Error('Failed to load Google Ad Manager script'));
    document.head.appendChild(script);
  });
}

async function loadImaSdk(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (typeof window === 'undefined') {
      reject(new Error('Window not available'));
      return;
    }

    // Check if already loaded
    if (window.google?.ima) {
      resolve();
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://imasdk.googleapis.com/js/sdkloader/ima3.js';
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load IMA SDK'));
    document.head.appendChild(script);
  });
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
      
      if (!appId && process.env.NODE_ENV === 'development') {
        console.warn('AdMob App ID not configured. Using test ad unit.');
      }

      await AdMob.start();
      adInitialized = true;
      if (process.env.NODE_ENV === 'development') {
        console.log('AdMob initialized');
      }
    } catch (error) {
      handleError(error, 'Failed to initialize AdMob');
      adInitialized = true;
    }
  } else {
    // Initialize web ads (Google Ad Manager)
    try {
      if (GAM_PUBLISHER_ID && GAM_REWARDED_AD_UNIT_ID) {
        await loadGoogleAdManagerScript();
        await loadImaSdk();
        if (process.env.NODE_ENV === 'development') {
          console.log('Google Ad Manager initialized for web');
        }
      } else if (process.env.NODE_ENV === 'development') {
        console.warn('Google Ad Manager not configured. Using mock ads.');
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('Failed to initialize Google Ad Manager, falling back to mock ads:', error);
      }
    }
    adInitialized = true;
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
    if (process.env.NODE_ENV === 'development') {
      console.log('Rewarded ad loaded');
    }
  } catch (error) {
    handleError(error, 'Failed to load rewarded ad');
    throw error;
  }
}

async function showWebRewardedAd(): Promise<void> {
  const { useAdOverlayStore } = await import('@/stores/useAdOverlayStore');
  const overlayStore = useAdOverlayStore.getState();

  // Check if Google Ad Manager is configured
  if (GAM_PUBLISHER_ID && GAM_REWARDED_AD_UNIT_ID && window.google?.ima) {
    return new Promise((resolve, reject) => {
      try {
        // Create ad container
        const adContainer = document.createElement('div');
        adContainer.id = 'rewarded-ad-container';
        adContainer.style.cssText = 'position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: 100000; background: black;';
        document.body.appendChild(adContainer);

        // Create video element
        const videoElement = document.createElement('video');
        videoElement.id = 'rewarded-ad-video';
        videoElement.style.cssText = 'width: 100%; height: 100%; object-fit: contain;';
        videoElement.controls = false;
        adContainer.appendChild(videoElement);

        // Initialize IMA SDK
        const ima = window.google!.ima!;
        const adDisplayContainer = new ima.AdDisplayContainer(adContainer, videoElement);
        const adsLoader = new ima.AdsLoader(adDisplayContainer);

        let adsManager: any;
        let cleanupCalled = false;

        function cleanup() {
          if (cleanupCalled) return;
          cleanupCalled = true;
          try {
            if (adsManager) {
              adsManager.destroy();
            }
            if (adContainer.parentNode) {
              adContainer.parentNode.removeChild(adContainer);
            }
          } catch (e) {
            console.error('Error during cleanup:', e);
          }
        }

        // Handle ads manager loaded
        adsLoader.addEventListener(ima.AdsManagerLoadedEvent.Type.ADS_MANAGER_LOADED, (event: any) => {
          try {
            adsManager = event.getAdsManager(videoElement);
            
            adsManager.addEventListener(ima.AdEvent.Type.STARTED, () => {
              // Ad started playing
            });
            
            adsManager.addEventListener(ima.AdEvent.Type.COMPLETE, () => {
              // Ad completed successfully
              cleanup();
              overlayStore.hideOverlay();
              resolve();
            });
            
            adsManager.addEventListener(ima.AdEvent.Type.ERROR, (error: any) => {
              console.error('Ad error:', error);
              cleanup();
              overlayStore.hideOverlay();
              reject(new Error('Ad failed to play'));
            });
            
            // Initialize and start the ad
            const width = adContainer.clientWidth || window.innerWidth;
            const height = adContainer.clientHeight || window.innerHeight;
            adsManager.init(width, height, ima.ViewMode.NORMAL);
            adsManager.start();
          } catch (e) {
            console.error('Error setting up ads manager:', e);
            cleanup();
            overlayStore.hideOverlay();
            reject(e);
          }
        });

        // Handle ads loader errors
        adsLoader.addEventListener(ima.AdsLoaderEvent.Type.ADS_LOADER_FAILED, (error: any) => {
          console.error('Ads loader failed:', error);
          cleanup();
          overlayStore.hideOverlay();
          reject(new Error('Failed to load ad'));
        });

        // Request ad
        const adsRequest = new ima.AdsRequest();
        adsRequest.adTagUrl = `https://pubads.g.doubleclick.net/gampad/ads?iu=${GAM_PUBLISHER_ID}/${GAM_REWARDED_AD_UNIT_ID}&env=vp&gdfp_req=1&output=xml_vast3&unviewed_position_start=1&url=${encodeURIComponent(window.location.href)}&description_url=${encodeURIComponent(window.location.href)}&correlator=${Date.now()}`;
        adsRequest.linearAdSlotWidth = adContainer.clientWidth || window.innerWidth;
        adsRequest.linearAdSlotHeight = adContainer.clientHeight || window.innerHeight;

        // Initialize and request ads
        adDisplayContainer.initialize();
        adsLoader.requestAds(adsRequest);

        // Show overlay
        overlayStore.showOverlay(DEFAULT_AD_DURATION);
      } catch (error) {
        overlayStore.hideOverlay();
        reject(error);
      }
    });
  } else {
    // Fallback to mock ad if GAM not configured
    const duration = DEFAULT_AD_DURATION;
    overlayStore.showOverlay(duration);
    
    return new Promise((resolve) => {
      setTimeout(() => {
        if (process.env.NODE_ENV === 'development') {
          console.log('Mock ad completed (GAM not configured)');
        }
        overlayStore.hideOverlay();
        resolve();
      }, duration);
    });
  }
}

export async function showRewardedAd(): Promise<void> {
  // Show overlay
  const { useAdOverlayStore } = await import('@/stores/useAdOverlayStore');
  const overlayStore = useAdOverlayStore.getState();
  
  if (!isMobile()) {
    // Use web ad implementation
    try {
      await showWebRewardedAd();
    } catch (error) {
      // Fallback to mock ad on error
      handleError(error, 'Failed to show web ad, using fallback');
      const duration = DEFAULT_AD_DURATION;
      overlayStore.showOverlay(duration);
      return new Promise((resolve) => {
        setTimeout(() => {
          overlayStore.hideOverlay();
          resolve();
        }, duration);
      });
    }
    return;
  }

  try {
    if (!rewardedAdLoaded) {
      await loadRewardedAd();
    }

    await loadCapacitorModules();
    
    if (!Capacitor || !AdMob) {
      overlayStore.hideOverlay();
      throw new Error('Capacitor modules not available');
    }

    const platform = Capacitor.getPlatform();
    const adUnitId = platform === 'ios' 
      ? (ADMOB_REWARDED_AD_UNIT_ID_IOS || ADMOB_TEST_REWARDED_AD_UNIT_ID)
      : (ADMOB_REWARDED_AD_UNIT_ID_ANDROID || ADMOB_TEST_REWARDED_AD_UNIT_ID);

    // Show overlay with estimated duration
    overlayStore.showOverlay(DEFAULT_AD_DURATION);

    return new Promise<void>((resolve, reject) => {
      if (!AdMob) {
        overlayStore.hideOverlay();
        reject(new Error('AdMob not available'));
        return;
      }

      const rewardListener = AdMob.addListener('onRewarded', (reward: { type: string; amount: number; adUnitId: string }) => {
        if (process.env.NODE_ENV === 'development') {
          console.log('Ad reward granted:', reward);
        }
        rewardListener.remove();
        overlayStore.hideOverlay();
        resolve();
      });

      AdMob.showRewardVideoAd()
        .then(() => {
          // Ad started playing, overlay is already shown
        })
        .catch((error: unknown) => {
          rewardListener.remove();
          overlayStore.hideOverlay();
          reject(error);
        });
    });
  } catch (error) {
    // Ensure overlay is hidden on any error
    overlayStore.hideOverlay();
    handleError(error, 'Failed to show rewarded ad');
    throw error;
  }
}

