/**
 * Isometric asset configuration
 * Maps building types and road types to their PixelLab asset IDs/URLs
 */

export interface BuildingAssetConfig {
  assetId?: string;
  imageUrl?: string;
  width: number;
  height: number;
  offsetX?: number;
  offsetY?: number;
}

export interface RoadAssetConfig {
  assetId?: string;
  imageUrl?: string;
  metadataUrl?: string;
  tileMap: Record<string, string>; // Maps road_type to tile image URL
}

export interface TerrainAssetConfig {
  tilesetId?: string;
  baseTileUrl?: string;
  metadataUrl?: string;
  tileMap: Record<string, string>; // Maps tile variant to image URL
}

/**
 * Building asset mappings
 * TODO: Replace placeholder URLs with actual PixelLab asset URLs once generated
 */
export const BUILDING_ASSETS: Record<string, BuildingAssetConfig> = {
  // Factory buildings (2x2 = 64x64px)
  rune_bakery: {
    assetId: '2fc0484d-32d7-4ec6-b744-05d1bcfcfd00',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/2fc0484d-32d7-4ec6-b744-05d1bcfcfd00/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  potion_workshop: {
    assetId: '51ddd985-da73-49ba-93d4-a7d49ad8a89b',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/51ddd985-da73-49ba-93d4-a7d49ad8a89b/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  enchanting_lab: {
    assetId: '3a78991c-396c-4ad6-980d-e1c08f6fa015',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/3a78991c-396c-4ad6-980d-e1c08f6fa015/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  kitchen: {
    assetId: 'b3060d6f-5fcc-4a7e-bf25-29604c775f01',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/b3060d6f-5fcc-4a7e-bf25-29604c775f01/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  
  // Community buildings
  town_hall: {
    assetId: 'd36d232f-ecfc-4479-b09c-6967674bc261',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/d36d232f-ecfc-4479-b09c-6967674bc261/download',
    width: 64, // Note: Generated at 64px due to tool limits, but represents 3x3 building (can be scaled in CSS)
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  school: {
    assetId: '6ddc2b80-d1cd-4070-9864-a58adb6638a0',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/6ddc2b80-d1cd-4070-9864-a58adb6638a0/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  hospital: {
    assetId: 'b50bfb73-b5fd-4bbf-8c97-335584f0bea8',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/b50bfb73-b5fd-4bbf-8c97-335584f0bea8/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  cinema: {
    assetId: '1aaf461e-7344-42bf-9aaa-fc6413d2b5e4',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/1aaf461e-7344-42bf-9aaa-fc6413d2b5e4/download',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  
  // Decorations (1x1 = 32x32px)
  fountain: {
    assetId: 'c95eb2eb-7c4a-4544-8707-2e76e6e23a46',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/c95eb2eb-7c4a-4544-8707-2e76e6e23a46/download',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  statue: {
    assetId: '95b45ea3-8b3e-4fad-9d6e-1849db36f5d2',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/95b45ea3-8b3e-4fad-9d6e-1849db36f5d2/download',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  tree: {
    assetId: 'f5767c88-144e-4bb9-8b77-572766aeef64',
    imageUrl: 'https://api.pixellab.ai/mcp/isometric-tile/f5767c88-144e-4bb9-8b77-572766aeef64/download',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
};

/**
 * Road asset mappings
 * Using the road tileset - individual tiles extracted from tileset PNG based on road_type
 */
export const ROAD_ASSETS: RoadAssetConfig = {
  assetId: 'c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0',
  imageUrl: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
  metadataUrl: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/metadata',
  tileMap: {
    // Road types from RoadTile component
    // All roads use the same tileset - individual tiles extracted via metadata
    straight_h: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    straight_v: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    corner_ne: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    corner_nw: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    corner_se: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    corner_sw: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    intersection: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    t_n: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    t_s: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    t_e: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
    t_w: 'https://api.pixellab.ai/mcp/tilesets/c0c5d4c0-223c-4b91-bb6e-4febc5eec8b0/image',
  },
};

/**
 * Terrain asset mappings
 * Using the grass tileset - individual tiles extracted from the tileset PNG using metadata
 */
export const TERRAIN_ASSETS: TerrainAssetConfig = {
  tilesetId: 'aba0fed5-1bff-4b7e-a511-1be94506491c',
  baseTileUrl: 'https://api.pixellab.ai/mcp/tilesets/aba0fed5-1bff-4b7e-a511-1be94506491c/image',
  metadataUrl: 'https://api.pixellab.ai/mcp/tilesets/aba0fed5-1bff-4b7e-a511-1be94506491c/metadata',
  tileMap: {
    grass: 'https://api.pixellab.ai/mcp/tilesets/aba0fed5-1bff-4b7e-a511-1be94506491c/image', // Full tileset - individual tiles extracted via metadata
  },
};

/**
 * Get building asset configuration
 */
export function getBuildingAsset(buildingType: string): BuildingAssetConfig | null {
  return BUILDING_ASSETS[buildingType] || null;
}

/**
 * Get road asset URL for a specific road type
 */
export function getRoadAsset(roadType: string): string | null {
  return ROAD_ASSETS.tileMap[roadType] || null;
}

/**
 * Get terrain asset URL for a specific terrain type
 */
export function getTerrainAsset(terrainType: string = 'grass'): string | null {
  return TERRAIN_ASSETS.tileMap[terrainType] || null;
}

