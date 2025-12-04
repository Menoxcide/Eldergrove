// Stub module for Capacitor packages in web builds
// These are only available in native environments
// This stub prevents build errors when Capacitor packages are dynamically imported

export const Capacitor = {
  isNativePlatform: () => false,
  getPlatform: () => 'web',
};

export const AdMob = {
  start: async () => {},
  prepareRewardVideoAd: async () => {},
  showRewardVideoAd: async () => {},
  addListener: () => ({ remove: () => {} }),
};


