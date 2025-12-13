/**
 * Isometric coordinate conversion utilities
 * Converts between grid coordinates (x, y) and isometric screen coordinates
 */

export interface IsometricPoint {
  x: number;
  y: number;
}

export interface GridPoint {
  x: number;
  y: number;
}

/**
 * Tile dimensions in pixels (isometric tile size)
 */
export const TILE_WIDTH = 32;
export const TILE_HEIGHT = 32;

/**
 * Isometric projection constants
 * For a standard isometric projection:
 * - X axis: 45 degrees rotated, scaled
 * - Y axis: 45 degrees rotated, scaled
 */
const ISO_ANGLE = Math.PI / 6; // 30 degrees
const ISO_SCALE_X = Math.cos(ISO_ANGLE);
const ISO_SCALE_Y = Math.sin(ISO_ANGLE);

/**
 * Convert grid coordinates to isometric screen coordinates
 * @param gridX Grid X coordinate (0-based)
 * @param gridY Grid Y coordinate (0-based)
 * @returns Isometric screen coordinates
 */
export function gridToIsometric(gridX: number, gridY: number): IsometricPoint {
  // Standard isometric projection formula
  const isoX = (gridX - gridY) * (TILE_WIDTH / 2);
  const isoY = (gridX + gridY) * (TILE_HEIGHT / 2);
  
  return { x: isoX, y: isoY };
}

/**
 * Convert isometric screen coordinates back to grid coordinates
 * @param isoX Isometric X coordinate
 * @param isoY Isometric Y coordinate
 * @returns Grid coordinates (may be fractional)
 */
export function isometricToGrid(isoX: number, isoY: number): GridPoint {
  // Inverse isometric projection
  const gridX = (isoX / (TILE_WIDTH / 2) + isoY / (TILE_HEIGHT / 2)) / 2;
  const gridY = (isoY / (TILE_HEIGHT / 2) - isoX / (TILE_WIDTH / 2)) / 2;
  
  return { x: gridX, y: gridY };
}

/**
 * Calculate z-index for proper depth sorting
 * Buildings further south (higher Y) should render on top
 * @param gridX Grid X coordinate
 * @param gridY Grid Y coordinate
 * @param gridSize Total grid size (for normalization)
 * @returns Z-index value (higher = renders on top)
 */
export function getZIndex(gridX: number, gridY: number, gridSize: number = 20): number {
  // Normalize to 0-1 range, then scale
  // Higher Y values (south) get higher z-index
  // Add X component for proper sorting when Y is equal
  const normalizedY = gridY / gridSize;
  const normalizedX = gridX / gridSize;
  return Math.floor((normalizedY * 1000) + (normalizedX * 10));
}

/**
 * Z-index constants for proper layering
 * Terrain: 0-999 (base layer)
 * Roads: 1000-1999 (above terrain)
 * Buildings: 2000+ (above roads and terrain)
 */
export const Z_INDEX_TERRAIN = 0;
export const Z_INDEX_ROAD_BASE = 1000;
export const Z_INDEX_BUILDING_BASE = 2000;

/**
 * Get z-index for terrain tiles
 * @param gridX Grid X coordinate
 * @param gridY Grid Y coordinate
 * @param gridSize Total grid size
 * @returns Z-index for terrain (0-999 range)
 */
export function getTerrainZIndex(gridX: number, gridY: number, gridSize: number = 20): number {
  return Z_INDEX_TERRAIN + getZIndex(gridX, gridY, gridSize);
}

/**
 * Get z-index for road tiles
 * @param gridX Grid X coordinate
 * @param gridY Grid Y coordinate
 * @param gridSize Total grid size
 * @returns Z-index for roads (1000-1999 range)
 */
export function getRoadZIndex(gridX: number, gridY: number, gridSize: number = 20): number {
  return Z_INDEX_ROAD_BASE + getZIndex(gridX, gridY, gridSize);
}

/**
 * Get z-index for buildings
 * @param gridX Grid X coordinate
 * @param gridY Grid Y coordinate
 * @param gridSize Total grid size
 * @returns Z-index for buildings (2000+ range)
 */
export function getBuildingZIndex(gridX: number, gridY: number, gridSize: number = 20): number {
  return Z_INDEX_BUILDING_BASE + getZIndex(gridX, gridY, gridSize);
}

/**
 * Calculate bounding box in isometric space for multi-tile buildings
 * @param gridX Top-left grid X coordinate
 * @param gridY Top-left grid Y coordinate
 * @param sizeX Width in grid tiles
 * @param sizeY Height in grid tiles
 * @returns Bounding box with top-left and bottom-right isometric coordinates
 */
export function getIsometricBoundingBox(
  gridX: number,
  gridY: number,
  sizeX: number,
  sizeY: number
): {
  topLeft: IsometricPoint;
  bottomRight: IsometricPoint;
  width: number;
  height: number;
} {
  const topLeft = gridToIsometric(gridX, gridY);
  const bottomRight = gridToIsometric(gridX + sizeX - 1, gridY + sizeY - 1);
  
  // Calculate actual width and height in isometric space
  const width = Math.abs(bottomRight.x - topLeft.x) + TILE_WIDTH;
  const height = Math.abs(bottomRight.y - topLeft.y) + TILE_HEIGHT;
  
  return {
    topLeft,
    bottomRight,
    width,
    height
  };
}

/**
 * Get the center point of a building in isometric space
 * @param gridX Top-left grid X coordinate
 * @param gridY Top-left grid Y coordinate
 * @param sizeX Width in grid tiles
 * @param sizeY Height in grid tiles
 * @returns Center point in isometric coordinates
 */
export function getBuildingCenter(
  gridX: number,
  gridY: number,
  sizeX: number,
  sizeY: number
): IsometricPoint {
  const centerGridX = gridX + (sizeX - 1) / 2;
  const centerGridY = gridY + (sizeY - 1) / 2;
  return gridToIsometric(centerGridX, centerGridY);
}

/**
 * Check if a point (in grid coordinates) is within a building's bounds
 * @param pointX Grid X coordinate to check
 * @param pointY Grid Y coordinate to check
 * @param buildingX Building's top-left grid X
 * @param buildingY Building's top-left grid Y
 * @param buildingSizeX Building's width in tiles
 * @param buildingSizeY Building's height in tiles
 * @returns True if point is within building bounds
 */
export function isPointInBuilding(
  pointX: number,
  pointY: number,
  buildingX: number,
  buildingY: number,
  buildingSizeX: number,
  buildingSizeY: number
): boolean {
  return (
    pointX >= buildingX &&
    pointX < buildingX + buildingSizeX &&
    pointY >= buildingY &&
    pointY < buildingY + buildingSizeY
  );
}

