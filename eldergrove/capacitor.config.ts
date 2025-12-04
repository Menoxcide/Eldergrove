import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.eldergrove.app',
  appName: 'Eldergrove',
  webDir: 'out',
  server: {
    androidScheme: 'https'
  },
  plugins: {
    AdMob: {
      appId: {
        ios: process.env.NEXT_PUBLIC_ADMOB_APP_ID_IOS || '',
        android: process.env.NEXT_PUBLIC_ADMOB_APP_ID_ANDROID || ''
      }
    }
  }
};

export default config;

