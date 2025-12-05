import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // reactCompiler: true, // Temporarily disabled to test stability
  
  // Static export for Capacitor mobile builds
  // This ensures Next.js builds to 'out' directory, matching capacitor.config.ts webDir setting
  output: 'export',
  
  // Configure Turbopack to stub Capacitor packages (native-only dependencies)
  turbopack: {
    resolveAlias: {
      // Map Capacitor packages to stub modules to prevent bundling errors
      // These are only available in native environments, so we use stubs for web builds
      '@capacitor/core': './src/lib/ads/capacitor-stub.ts',
      '@capgo/capacitor-admob': './src/lib/ads/capacitor-stub.ts',
      '@capacitor/app': './src/lib/ads/capacitor-stub.ts',
      '@capacitor/cli': './src/lib/ads/capacitor-stub.ts',
    },
  },
  
  // Note: headers() function is not compatible with static export (output: 'export')
  // Headers for static sites should be configured at the hosting/CDN level
};

export default nextConfig;
