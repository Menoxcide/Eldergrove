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
    imageUrl: '/assets/buildings/rune_bakery.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  potion_workshop: {
    assetId: '51ddd985-da73-49ba-93d4-a7d49ad8a89b',
    imageUrl: '/assets/buildings/potion_workshop.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  enchanting_lab: {
    assetId: '3a78991c-396c-4ad6-980d-e1c08f6fa015',
    imageUrl: '/assets/buildings/enchanting_lab.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  kitchen: {
    assetId: 'b3060d6f-5fcc-4a7e-bf25-29604c775f01',
    imageUrl: '/assets/buildings/kitchen.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  
  // Community buildings
  town_hall: {
    assetId: 'd36d232f-ecfc-4479-b09c-6967674bc261',
    imageUrl: '/assets/buildings/town_hall.png',
    width: 64, // Note: Generated at 64px due to tool limits, but represents 3x3 building (can be scaled in CSS)
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  school: {
    assetId: '6ddc2b80-d1cd-4070-9864-a58adb6638a0',
    imageUrl: '/assets/buildings/school.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  hospital: {
    assetId: 'b50bfb73-b5fd-4bbf-8c97-335584f0bea8',
    imageUrl: '/assets/buildings/hospital.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  cinema: {
    assetId: '1aaf461e-7344-42bf-9aaa-fc6413d2b5e4',
    imageUrl: '/assets/buildings/cinema.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },

  // Additional buildings
  cottage: {
    assetId: '66674d1d-e786-4aa9-9ac0-9b630181c1f0',
    imageUrl: '/assets/buildings/cottage.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },

  // Required game buildings (2x2 = 64x64px)
  farm: {
    assetId: 'a8353066-fd41-46c2-937f-13c2c162257c',
    imageUrl: '/assets/buildings/farm.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  factory: {
    assetId: 'b3a69e23-fd26-4a4f-806f-a82bf415c47c',
    imageUrl: '/assets/buildings/factory.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  mine: {
    assetId: '64856f6b-18e7-4757-9380-dcfbcae8e133',
    imageUrl: '/assets/buildings/mine.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  armory: {
    assetId: 'da98a0c3-3435-4c5f-98a9-2e7936a1763c',
    imageUrl: '/assets/buildings/armory.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  zoo: {
    assetId: 'f48af267-d902-4091-aa0b-af1a2dec5fa2',
    imageUrl: '/assets/buildings/zoo.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },
  coven: {
    assetId: '985df9a5-bea5-4287-8913-e48d8174a482',
    imageUrl: '/assets/buildings/coven.png',
    width: 64,
    height: 64,
    offsetX: 0,
    offsetY: 0,
  },

  // Decorations (1x1 = 32x32px)
  fountain: {
    assetId: 'c95eb2eb-7c4a-4544-8707-2e76e6e23a46',
    imageUrl: '/assets/buildings/fountain.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  statue: {
    assetId: '95b45ea3-8b3e-4fad-9d6e-1849db36f5d2',
    imageUrl: '/assets/buildings/statue.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  tree: {
    assetId: 'f5767c88-144e-4bb9-8b77-572766aeef64',
    imageUrl: '/assets/buildings/tree.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },

  // Additional decorations
  bench: {
    assetId: '58bd0b6a-43c0-4cc8-bfeb-8aad9c1f7213',
    imageUrl: '/assets/buildings/bench.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  well: {
    assetId: '36ab9e18-b82c-4c43-80e8-653033e81fa3',
    imageUrl: '/assets/buildings/well.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  barrel: {
    assetId: 'a956294a-1cdb-40b6-a9b7-7f0908250b9a',
    imageUrl: '/assets/buildings/barrel.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  crate: {
    assetId: 'b8f4d056-0fae-494d-9c52-fb65d81bc557',
    imageUrl: '/assets/buildings/crate.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  fence: {
    assetId: 'ee698dde-f49f-43f3-98cc-13078b17e182',
    imageUrl: '/assets/buildings/fence.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  sign_post: {
    assetId: 'e26c8a33-e9e8-4b85-b666-193dfc3dc7fa',
    imageUrl: '/assets/buildings/sign_post.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  campfire: {
    assetId: 'd8e5ae0b-09df-42f2-af1c-6f1c6d4e98aa',
    imageUrl: '/assets/buildings/campfire.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },

  // Tree variants
  oak_tree: {
    assetId: '0de594d9-d3af-4e80-937d-927ab89ccd16',
    imageUrl: '/assets/buildings/oak_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  pine_tree: {
    assetId: '2aacd7a5-0b64-4441-a279-975053a11fee',
    imageUrl: '/assets/buildings/pine_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  birch_tree: {
    assetId: '25f64456-cd56-4c7b-b693-d45c8b933886',
    imageUrl: '/assets/buildings/birch_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  palm_tree: {
    assetId: '4db31b5a-bc0d-405a-9257-10381d880505',
    imageUrl: '/assets/buildings/palm_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  willow_tree: {
    assetId: 'b5d0ceae-44b3-4c71-ae0c-6ab708c856ee',
    imageUrl: '/assets/buildings/willow_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },

  // Flower variants
  blue_flower: {
    assetId: 'eb1321d5-7857-49b6-a8ca-f6b7fb2d0324',
    imageUrl: '/assets/buildings/blue_flower.png',
    width: 16,
    height: 16,
    offsetX: 0,
    offsetY: 0,
  },
  yellow_flower: {
    assetId: '9a4eae15-e0e4-4d98-8b16-70b4156e6f9f',
    imageUrl: '/assets/buildings/yellow_flower.png',
    width: 16,
    height: 16,
    offsetX: 0,
    offsetY: 0,
  },
  red_flower: {
    assetId: 'd8392f38-962c-434b-935f-aba3f95c3dc1',
    imageUrl: '/assets/buildings/red_flower.png',
    width: 16,
    height: 16,
    offsetX: 0,
    offsetY: 0,
  },

  // Mushroom variants
  brown_mushroom: {
    assetId: '48da9462-ebed-41b5-be80-0d62a9d43d35',
    imageUrl: '/assets/buildings/brown_mushroom.png',
    width: 24,
    height: 24,
    offsetX: 0,
    offsetY: 0,
  },
  red_mushroom: {
    assetId: 'b447a213-25c0-4224-af70-445fa8c8522b',
    imageUrl: '/assets/buildings/red_mushroom.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },

  // Rock/boulder variants
  dead_tree: {
    assetId: '37760e8a-05c6-4234-b4bd-4c0e4bd5fb1b',
    imageUrl: '/assets/buildings/dead_tree.png',
    width: 48,
    height: 48,
    offsetX: 0,
    offsetY: 0,
  },
  small_rock: {
    assetId: '8688deae-8d2b-430a-a267-d07f2626b627',
    imageUrl: '/assets/buildings/small_rock.png',
    width: 24,
    height: 24,
    offsetX: 0,
    offsetY: 0,
  },
  large_boulder: {
    assetId: '30fe1f09-fb9f-45f7-aad4-29445df35e0e',
    imageUrl: '/assets/buildings/large_boulder.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },

  // Bush variants
  green_bush: {
    assetId: '7200263b-a3de-4ced-917f-967b08661e14',
    imageUrl: '/assets/buildings/green_bush.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  thorny_bush: {
    assetId: 'af938366-bff7-4c61-b75a-cf4bbf30573e',
    imageUrl: '/assets/buildings/thorny_bush.png',
    width: 32,
    height: 32,
    offsetX: 0,
    offsetY: 0,
  },
  flowering_bush: {
    assetId: '0af6596c-9409-496d-b9b8-6383fb1c0179',
    imageUrl: '/assets/buildings/flowering_bush.png',
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
  imageUrl: '/assets/roads/roads_tileset.png',
  metadataUrl: '/assets/roads/roads_metadata.json',
  tileMap: {
    // Road types from RoadTile component
    // All roads use the same tileset - individual tiles extracted via metadata
    straight_h: '/assets/roads/roads_tileset.png',
    straight_v: '/assets/roads/roads_tileset.png',
    corner_ne: '/assets/roads/roads_tileset.png',
    corner_nw: '/assets/roads/roads_tileset.png',
    corner_se: '/assets/roads/roads_tileset.png',
    corner_sw: '/assets/roads/roads_tileset.png',
    intersection: '/assets/roads/roads_tileset.png',
    t_n: '/assets/roads/roads_tileset.png',
    t_s: '/assets/roads/roads_tileset.png',
    t_e: '/assets/roads/roads_tileset.png',
    t_w: '/assets/roads/roads_tileset.png',
  },
};

/**
 * Terrain asset mappings
 * Using the grass tileset - individual tiles extracted from the tileset PNG using metadata
 */
export const TERRAIN_ASSETS: TerrainAssetConfig = {
  tilesetId: 'aba0fed5-1bff-4b7e-a511-1be94506491c',
  baseTileUrl: '/assets/terrain/grass_tileset.png',
  metadataUrl: '/assets/terrain/grass_metadata.json',
  tileMap: {
    grass: '/assets/terrain/grass_tileset.png', // Full tileset - individual tiles extracted via metadata
  },
};

/**
 * Additional terrain tilesets
 */
export const ADDITIONAL_TERRAIN_ASSETS: Record<string, TerrainAssetConfig> = {
  // Stone/cobblestone paths
  stone_cobblestone: {
    tilesetId: 'ac2712aa-4ac5-4bd1-806d-0f4a5b6a0968',
    baseTileUrl: '/assets/terrain/stone_tileset.png',
    metadataUrl: '/assets/terrain/stone_metadata.json',
    tileMap: {
      stone_path: '/assets/terrain/stone_tileset.png',
    },
  },

  // Dirt paths
  dirt_path: {
    tilesetId: 'ef3a6f10-2d18-48da-baea-3160e60805ac',
    baseTileUrl: '/assets/terrain/dirt_tileset.png',
    metadataUrl: '/assets/terrain/dirt_metadata.json',
    tileMap: {
      dirt_path: '/assets/terrain/dirt_tileset.png',
    },
  },

  // Beach/sand terrain
  sandy_beach: {
    tilesetId: 'c6494ffa-9ad5-4e73-859f-ee1d3713e055',
    baseTileUrl: '/assets/terrain/sand_tileset.png',
    metadataUrl: '/assets/terrain/sand_metadata.json',
    tileMap: {
      sand: '/assets/terrain/sand_tileset.png',
    },
  },

  // Water/ocean terrain
  ocean_water: {
    tilesetId: '345e398d-01e3-4566-b0a2-57d328da77b5',
    baseTileUrl: '/assets/terrain/water_tileset.png',
    metadataUrl: '/assets/terrain/water_metadata.json',
    tileMap: {
      water: '/assets/terrain/water_tileset.png',
    },
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

