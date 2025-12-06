// Stub module for Capacitor packages in web builds

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


