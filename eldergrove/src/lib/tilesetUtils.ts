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
  format?: string;
  tiles: TileMetadata[];
  tileset_data?: {
    tiles: TileMetadata[];
    tile_size?: {
      width: number;
      height: number;
    };
    total_tiles?: number;
    terrain_types?: string[];
  };
  tileset_image?: {
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
 * Includes retry logic and better error handling for CORS issues
 */
export async function extractTileImage(
  tilesetImageUrl: string,
  tileMetadata: TileMetadata,
  retries: number = 2
): Promise<string> {
  return new Promise((resolve, reject) => {
    const attemptLoad = (attempt: number) => {
      const img = new Image();
      
      // Try with CORS first, fallback to no CORS if that fails
      if (attempt === 0) {
        img.crossOrigin = 'anonymous';
      }
      
      img.onload = () => {
        try {
          const canvas = document.createElement('canvas');
          canvas.width = tileMetadata.bounding_box.width;
          canvas.height = tileMetadata.bounding_box.height;
          const ctx = canvas.getContext('2d');
          
          if (!ctx) {
            if (attempt < retries) {
              attemptLoad(attempt + 1);
            } else {
              reject(new Error('Could not get canvas context'));
            }
            return;
          }
          
          // Validate bounding box
          if (
            tileMetadata.bounding_box.x < 0 ||
            tileMetadata.bounding_box.y < 0 ||
            tileMetadata.bounding_box.width <= 0 ||
            tileMetadata.bounding_box.height <= 0
          ) {
            reject(new Error('Invalid tile bounding box'));
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
        } catch (error) {
          if (attempt < retries) {
            attemptLoad(attempt + 1);
          } else {
            reject(error instanceof Error ? error : new Error('Failed to extract tile'));
          }
        }
      };
      
      img.onerror = (error) => {
        if (attempt < retries) {
          // Retry without CORS if first attempt failed
          attemptLoad(attempt + 1);
        } else {
          const errorMsg = error instanceof Error ? error.message : 'Failed to load tileset image';
          console.warn(`Failed to load tileset image after ${retries + 1} attempts:`, errorMsg);
          reject(new Error(errorMsg));
        }
      };
      
      img.src = tilesetImageUrl;
    };
    
    attemptLoad(0);
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
 * Includes retry logic and better error handling
 */
export async function loadTilesetMetadata(
  metadataUrl: string,
  retries: number = 2
): Promise<TilesetMetadata> {
  let lastError: Error | null = null;
  
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const response = await fetch(metadataUrl, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
        },
      });
      
      if (!response.ok) {
        throw new Error(`Failed to load tileset metadata: ${response.status} ${response.statusText}`);
      }
      
      const rawMetadata = await response.json();
      
      // Normalize metadata structure - handle both formats:
      // 1. Direct format: { tiles: [...] }
      // 2. Nested format: { tileset_data: { tiles: [...] } }
      let tiles: TileMetadata[] | undefined;
      
      if (rawMetadata.tiles && Array.isArray(rawMetadata.tiles)) {
        // Direct format
        tiles = rawMetadata.tiles;
      } else if (rawMetadata.tileset_data?.tiles && Array.isArray(rawMetadata.tileset_data.tiles)) {
        // Nested format - extract tiles from tileset_data
        tiles = rawMetadata.tileset_data.tiles;
      }
      
      if (!tiles || tiles.length === 0) {
        throw new Error('Invalid tileset metadata: missing tiles array');
      }
      
      // Return normalized metadata structure
      const normalizedMetadata: TilesetMetadata = {
        ...rawMetadata,
        tiles,
        // Preserve tileset_data if it exists for other uses
        tileset_data: rawMetadata.tileset_data,
      };
      
      return normalizedMetadata;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error('Unknown error loading metadata');
      if (attempt < retries) {
        // Wait before retry (exponential backoff)
        await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 100));
      }
    }
  }
  
  throw lastError || new Error('Failed to load tileset metadata after retries');
}

