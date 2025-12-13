import { create } from 'zustand';
import { BUILDING_ASSETS, ROAD_ASSETS, TERRAIN_ASSETS, ADDITIONAL_TERRAIN_ASSETS, type BuildingAssetConfig } from '@/config/isometricAssets';

// Image cache for preloaded images
const imageCache = new Map<string, HTMLImageElement>();

/**
 * Preload an image and cache it
 */
async function preloadImage(url: string): Promise<HTMLImageElement> {
  if (imageCache.has(url)) {
    return imageCache.get(url)!;
  }
  
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      imageCache.set(url, img);
      resolve(img);
    };
    img.onerror = reject;
    img.src = url;
  });
}

interface AssetState {
  // Asset loading state
  buildingAssetsLoaded: Record<string, boolean>;
  roadAssetsLoaded: boolean;
  terrainAssetsLoaded: boolean;
  
  // Asset URLs (populated when assets are loaded)
  buildingAssetUrls: Record<string, string>;
  roadAssetUrls: Record<string, string>;
  terrainAssetUrls: Record<string, string>;
  
  // Preloading state
  preloadingAssets: Set<string>;
  
  // Actions
  setBuildingAssetUrl: (buildingType: string, url: string) => void;
  setRoadAssetUrl: (roadType: string, url: string) => void;
  setTerrainAssetUrl: (terrainType: string, url: string) => void;
  markBuildingAssetLoaded: (buildingType: string) => void;
  markRoadAssetsLoaded: () => void;
  markTerrainAssetsLoaded: () => void;
  isBuildingAssetLoaded: (buildingType: string) => boolean;
  areRoadAssetsLoaded: () => boolean;
  areTerrainAssetsLoaded: () => boolean;
  getBuildingAssetUrl: (buildingType: string) => string | null;
  getRoadAssetUrl: (roadType: string) => string | null;
  getTerrainAssetUrl: (terrainType?: string) => string | null;
  getAdditionalTerrainAssetUrl: (terrainType: string) => string | null;
  preloadBuildingAssets: () => Promise<void>;
  preloadAllAssets: () => Promise<void>;
  getCachedImage: (url: string) => HTMLImageElement | null;
}

export const useAssetStore = create<AssetState>((set, get) => ({
  buildingAssetsLoaded: {},
  roadAssetsLoaded: false,
  terrainAssetsLoaded: false,
  buildingAssetUrls: {},
  roadAssetUrls: {},
  terrainAssetUrls: {},
  preloadingAssets: new Set(),
  
  setBuildingAssetUrl: (buildingType, url) =>
    set((state) => ({
      buildingAssetUrls: {
        ...state.buildingAssetUrls,
        [buildingType]: url,
      },
    })),
  
  setRoadAssetUrl: (roadType, url) =>
    set((state) => ({
      roadAssetUrls: {
        ...state.roadAssetUrls,
        [roadType]: url,
      },
    })),
  
  setTerrainAssetUrl: (terrainType, url) =>
    set((state) => ({
      terrainAssetUrls: {
        ...state.terrainAssetUrls,
        [terrainType]: url,
      },
    })),
  
  markBuildingAssetLoaded: (buildingType) =>
    set((state) => ({
      buildingAssetsLoaded: {
        ...state.buildingAssetsLoaded,
        [buildingType]: true,
      },
    })),
  
  markRoadAssetsLoaded: () =>
    set({ roadAssetsLoaded: true }),
  
  markTerrainAssetsLoaded: () =>
    set({ terrainAssetsLoaded: true }),
  
  isBuildingAssetLoaded: (buildingType) => {
    const state = get();
    return state.buildingAssetsLoaded[buildingType] === true;
  },
  
  areRoadAssetsLoaded: () => {
    const state = get();
    return state.roadAssetsLoaded;
  },
  
  areTerrainAssetsLoaded: () => {
    const state = get();
    return state.terrainAssetsLoaded;
  },
  
  getBuildingAssetUrl: (buildingType) => {
    const state = get();
    // First check store URLs, then fall back to config
    return (
      state.buildingAssetUrls[buildingType] ||
      BUILDING_ASSETS[buildingType]?.imageUrl ||
      null
    );
  },
  
  getRoadAssetUrl: (roadType) => {
    const state = get();
    // First check store URLs, then fall back to config
    return (
      state.roadAssetUrls[roadType] ||
      ROAD_ASSETS.tileMap[roadType] ||
      null
    );
  },
  
  getTerrainAssetUrl: (terrainType = 'grass') => {
    const state = get();
    // First check store URLs, then fall back to config
    return (
      state.terrainAssetUrls[terrainType] ||
      TERRAIN_ASSETS.tileMap[terrainType] ||
      null
    );
  },

  getAdditionalTerrainAssetUrl: (terrainType: string) => {
    const state = get();
    // First check store URLs, then fall back to config
    const additionalTerrain = ADDITIONAL_TERRAIN_ASSETS[terrainType];
    if (!additionalTerrain) return null;

    return (
      state.terrainAssetUrls[terrainType] ||
      additionalTerrain.tileMap[terrainType] ||
      null
    );
  },
  
  preloadBuildingAssets: async () => {
    const state = get();
    const preloadPromises: Promise<void>[] = [];
    
    // Preload all building assets with retry logic
    Object.entries(BUILDING_ASSETS).forEach(([buildingType, config]) => {
      if (config.imageUrl && !state.preloadingAssets.has(config.imageUrl)) {
        state.preloadingAssets.add(config.imageUrl);
        preloadPromises.push(
          preloadImage(config.imageUrl)
            .then(() => {
              get().markBuildingAssetLoaded(buildingType);
            })
            .catch((error) => {
              console.warn(`[useAssetStore] Failed to preload building asset for ${buildingType}:`, error);
              // Don't throw - allow fallback rendering
            })
        );
      }
    });
    
    await Promise.allSettled(preloadPromises);
  },
  
  preloadAllAssets: async () => {
    const state = get();

    try {
      // Preload buildings
      await get().preloadBuildingAssets();
    } catch (error) {
      console.warn('[useAssetStore] Error preloading building assets:', error);
    }

    try {
      // Preload main terrain tileset
      if (TERRAIN_ASSETS.baseTileUrl && !state.preloadingAssets.has(TERRAIN_ASSETS.baseTileUrl)) {
        state.preloadingAssets.add(TERRAIN_ASSETS.baseTileUrl);
        await preloadImage(TERRAIN_ASSETS.baseTileUrl)
          .then(() => get().markTerrainAssetsLoaded())
          .catch((error) => {
            console.warn('[useAssetStore] Failed to preload terrain tileset:', error);
            // Don't throw - allow fallback rendering
          });
      }
    } catch (error) {
      console.warn('[useAssetStore] Error preloading terrain assets:', error);
    }

    try {
      // Preload additional terrain tilesets
      const additionalTerrainPromises = Object.entries(ADDITIONAL_TERRAIN_ASSETS).map(async ([terrainType, config]) => {
        if (config.baseTileUrl && !state.preloadingAssets.has(config.baseTileUrl)) {
          state.preloadingAssets.add(config.baseTileUrl);
          return preloadImage(config.baseTileUrl)
            .catch((error) => {
              console.warn(`[useAssetStore] Failed to preload additional terrain tileset ${terrainType}:`, error);
            });
        }
      });

      await Promise.allSettled(additionalTerrainPromises);
    } catch (error) {
      console.warn('[useAssetStore] Error preloading additional terrain assets:', error);
    }

    try {
      // Preload road tileset
      if (ROAD_ASSETS.imageUrl && !state.preloadingAssets.has(ROAD_ASSETS.imageUrl)) {
        state.preloadingAssets.add(ROAD_ASSETS.imageUrl);
        await preloadImage(ROAD_ASSETS.imageUrl)
          .then(() => get().markRoadAssetsLoaded())
          .catch((error) => {
            console.warn('[useAssetStore] Failed to preload road tileset:', error);
            // Don't throw - allow fallback rendering
          });
      }
    } catch (error) {
      console.warn('[useAssetStore] Error preloading road assets:', error);
    }
  },
  
  getCachedImage: (url: string) => {
    return imageCache.get(url) || null;
  },
}));

