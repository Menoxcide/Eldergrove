import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // reactCompiler: true, // Temporarily disabled to test stability
  
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
  
};

export default nextConfig;
