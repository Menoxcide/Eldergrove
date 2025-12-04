import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  reactCompiler: true,
  
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
  
  // Add headers for better caching
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=0, must-revalidate',
          },
        ],
      },
      {
        source: '/_next/static/(.*)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      {
        source: '/assets/(.*)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=86400, must-revalidate',
          },
        ],
      },
    ];
  },
};

export default nextConfig;
