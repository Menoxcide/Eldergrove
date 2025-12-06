/**
 * Utilities for extracting individual tiles from PixelLab tileset images
 * Uses metadata JSON to determine which tile to extract based on corner types
 */

export interface TileMetadata {
  id: string;
  corners: {
    NE: string;
    NW: string;
    SE: string;
    SW: string;
  };
  bounding_box: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

export interface TilesetMetadata {
  format: string;
  tiles: TileMetadata[];
  tileset_image: {
    filename: string;
    dimensions: {
      width: number;
      height: number;
    };
  };
  layout?: {
    width: number;
    height: number;
  };
}

/**
 * Get terrain tile based on corner values
 * For grass terrain: lower = dirt, upper = grass
 */
export function getTerrainTile(
  corners: { NE: string; NW: string; SE: string; SW: string },
  metadata: TilesetMetadata
): TileMetadata | null {
  return (
    metadata.tiles.find(
      (tile) =>
        tile.corners.NE === corners.NE &&
        tile.corners.NW === corners.NW &&
        tile.corners.SE === corners.SE &&
        tile.corners.SW === corners.SW
    ) || null
  );
}

/**
 * Get road tile based on corner values
 * For roads: lower = grass, upper = road
 */
export function getRoadTile(
  corners: { NE: string; NW: string; SE: string; SW: string },
  metadata: TilesetMetadata
): TileMetadata | null {
  return getTerrainTile(corners, metadata);
}

/**
 * Create a data URL for a specific tile from a tileset image
 * This extracts a tile region from the tileset PNG using canvas
 */
export async function extractTileImage(
  tilesetImageUrl: string,
  tileMetadata: TileMetadata
): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = tileMetadata.bounding_box.width;
      canvas.height = tileMetadata.bounding_box.height;
      const ctx = canvas.getContext('2d');
      
      if (!ctx) {
        reject(new Error('Could not get canvas context'));
        return;
      }
      
      ctx.drawImage(
        img,
        tileMetadata.bounding_box.x,
        tileMetadata.bounding_box.y,
        tileMetadata.bounding_box.width,
        tileMetadata.bounding_box.height,
        0,
        0,
        tileMetadata.bounding_box.width,
        tileMetadata.bounding_box.height
      );
      
      resolve(canvas.toDataURL('image/png'));
    };
    
    img.onerror = () => reject(new Error('Failed to load tileset image'));
    img.src = tilesetImageUrl;
  });
}

/**
 * Determine corner values for a terrain cell based on neighbors
 * Returns corner terrain types: "lower" (dirt) or "upper" (grass)
 */
export function getTerrainCorners(
  gridX: number,
  gridY: number,
  gridSize: number,
  terrainGrid: boolean[][] // true = grass, false = dirt
): { NE: string; NW: string; SE: string; SW: string } {
  // Sample corners from terrain grid
  // NW corner: (gridX, gridY)
  // NE corner: (gridX + 1, gridY)
  // SW corner: (gridX, gridY + 1)
  // SE corner: (gridX + 1, gridY + 1)
  
  const getTerrainType = (x: number, y: number): string => {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) {
      return 'lower'; // Default to dirt at edges
    }
    return terrainGrid[y]?.[x] ? 'upper' : 'lower';
  };
  
  return {
    NW: getTerrainType(gridX, gridY),
    NE: getTerrainType(gridX + 1, gridY),
    SW: getTerrainType(gridX, gridY + 1),
    SE: getTerrainType(gridX + 1, gridY + 1),
  };
}

/**
 * Determine corner values for a road cell based on neighbors
 * Returns corner types: "lower" (grass) or "upper" (road)
 */
export function getRoadCorners(
  gridX: number,
  gridY: number,
  gridSize: number,
  roadGrid: boolean[][] // true = road, false = grass
): { NE: string; NW: string; SE: string; SW: string } {
  const getRoadType = (x: number, y: number): string => {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) {
      return 'lower'; // Default to grass at edges
    }
    return roadGrid[y]?.[x] ? 'upper' : 'lower';
  };
  
  return {
    NW: getRoadType(gridX, gridY),
    NE: getRoadType(gridX + 1, gridY),
    SW: getRoadType(gridX, gridY + 1),
    SE: getRoadType(gridX + 1, gridY + 1),
  };
}

/**
 * Load tileset metadata from URL
 */
export async function loadTilesetMetadata(metadataUrl: string): Promise<TilesetMetadata> {
  const response = await fetch(metadataUrl);
  if (!response.ok) {
    throw new Error(`Failed to load tileset metadata: ${response.statusText}`);
  }
  return response.json();
}

