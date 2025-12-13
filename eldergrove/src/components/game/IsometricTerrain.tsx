'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { gridToIsometric, TILE_WIDTH, TILE_HEIGHT, getTerrainZIndex } from '@/lib/isometricUtils';
import { useAssetStore } from '@/stores/useAssetStore';
import { getTerrainCorners, getTerrainTile, extractTileImage, loadTilesetMetadata, type TilesetMetadata } from '@/lib/tilesetUtils';
import { TERRAIN_ASSETS } from '@/config/isometricAssets';

interface IsometricTerrainProps {
  gridX: number;
  gridY: number;
  gridSize: number;
  terrainType?: string;
  className?: string;
  // Terrain context for autotiling
  hasRoadNorth?: boolean;
  hasRoadSouth?: boolean;
  hasRoadEast?: boolean;
  hasRoadWest?: boolean;
  isAtMapEdge?: boolean;
  hasBuilding?: boolean;
}

const IsometricTerrain: React.FC<IsometricTerrainProps> = ({
  gridX,
  gridY,
  gridSize,
  terrainType = 'grass',
  className = '',
  hasRoadNorth = false,
  hasRoadSouth = false,
  hasRoadEast = false,
  hasRoadWest = false,
  isAtMapEdge = false,
  hasBuilding = false,
}) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);
  const [tileImageUrl, setTileImageUrl] = useState<string | null>(null);
  const [metadata, setMetadata] = useState<TilesetMetadata | null>(null);
  const getTerrainAssetUrl = useAssetStore((state) => state.getTerrainAssetUrl);
  const getAdditionalTerrainAssetUrl = useAssetStore((state) => state.getAdditionalTerrainAssetUrl);
  const getCachedImage = useAssetStore((state) => state.getCachedImage);
  const baseAssetUrl = getTerrainAssetUrl(terrainType) || getAdditionalTerrainAssetUrl(terrainType);
  
  // Calculate isometric position (memoized)
  const isoPos = useMemo(() => gridToIsometric(gridX, gridY), [gridX, gridY]);

  // Determine corner values for Wang tile selection
  // The tileset is "dirt → grass" transition, where:
  // - 'lower' = dirt (base terrain)
  // - 'upper' = grass (appears as paths/patches on dirt)
  // For a uniform grass base, we need all corners as 'upper' to get the all-grass tile
  // But if that still shows paths, we'll use a simpler approach
  const corners = useMemo(() => {
    // For interior tiles, use all 'upper' corners to get the all-grass tile
    // This should select tile "4e8898d0-772f-47ae-9898-d996ae227b8c" (wang_15) which is all grass
    if (!isAtMapEdge) {
      // All interior tiles should be all grass
      return {
        NW: 'upper',
        NE: 'upper',
        SW: 'upper',
        SE: 'upper',
      };
    }

    // At map edges, use dirt (lower) for transitions
    const getCornerValue = (cornerX: number, cornerY: number): string => {
      if (cornerX < 0 || cornerX >= gridSize || cornerY < 0 || cornerY >= gridSize) {
        return 'lower'; // Dirt at edges
      }
      if (cornerX === 0 || cornerX === gridSize - 1 || cornerY === 0 || cornerY === gridSize - 1) {
        return 'lower'; // Dirt at map edges
      }
      return 'upper'; // Grass in interior
    };

    return {
      NW: getCornerValue(gridX, gridY),
      NE: getCornerValue(gridX + 1, gridY),
      SW: getCornerValue(gridX, gridY + 1),
      SE: getCornerValue(gridX + 1, gridY + 1),
    };
  }, [gridX, gridY, gridSize, isAtMapEdge]);

  // Load tileset metadata and extract appropriate tile
  // For interior tiles, use CSS fallback (pure grass) to avoid transition tileset artifacts
  // Only use Wang tiles for edge transitions
  useEffect(() => {
    if (!baseAssetUrl || terrainType !== 'grass') {
      // For non-grass terrain or no asset URL, use fallback
      setTileImageUrl(null);
      setMetadata(null);
      setImageError(false);
      return;
    }

    // For interior tiles (not at edge), use CSS fallback for pure grass
    // This avoids the transition tileset showing grass paths on dirt
    if (!isAtMapEdge) {
      setTileImageUrl(null);
      setMetadata(null);
      setImageError(false);
      return;
    }

    // Only use Wang tiles for edge transitions
    const metadataUrl = TERRAIN_ASSETS.metadataUrl;
    if (!metadataUrl) {
      setTileImageUrl(null);
      setMetadata(null);
      setImageError(false);
      return;
    }

    let cancelled = false;

    // Load metadata with retry logic
    loadTilesetMetadata(metadataUrl, 2)
      .then((loadedMetadata) => {
        if (cancelled) return;
        
        setMetadata(loadedMetadata);
        
        // Find matching tile based on corners
        const tile = getTerrainTile(corners, loadedMetadata);
        if (tile && TERRAIN_ASSETS.baseTileUrl) {
          // Extract tile image with retry logic
          extractTileImage(TERRAIN_ASSETS.baseTileUrl, tile, 2)
            .then((dataUrl) => {
              if (cancelled) return;
              setTileImageUrl(dataUrl);
              setImageLoaded(true);
              setImageError(false);
            })
            .catch((error) => {
              if (cancelled) return;
              console.warn(`[IsometricTerrain] Failed to extract tile image at (${gridX}, ${gridY}):`, error);
              // Fallback to CSS
              setTileImageUrl(null);
              setImageError(false);
            });
        } else {
          // Fallback to CSS if no matching tile found
          if (!cancelled) {
            setTileImageUrl(null);
            setImageError(false);
          }
        }
      })
      .catch((error) => {
        if (cancelled) return;
        console.warn(`[IsometricTerrain] Failed to load tileset metadata at (${gridX}, ${gridY}):`, error);
        // Fallback to CSS
        setTileImageUrl(null);
        setImageError(false);
      });

    return () => {
      cancelled = true;
    };
  }, [baseAssetUrl, terrainType, corners, gridX, gridY, isAtMapEdge]);
  
  // Load tile image if we have a data URL
  useEffect(() => {
    if (tileImageUrl) {
      const cached = getCachedImage(tileImageUrl);
      if (cached) {
        setImageLoaded(true);
        setImageError(false);
        return;
      }
      
      // Load image
      setImageLoaded(false);
      setImageError(false);
      const img = new Image();
      img.onload = () => setImageLoaded(true);
      img.onerror = () => setImageError(true);
      img.src = tileImageUrl;
    } else if (baseAssetUrl) {
      // Fallback to base asset URL
      const cached = getCachedImage(baseAssetUrl);
      if (cached) {
        setImageLoaded(true);
        setImageError(false);
        return;
      }
      
      setImageLoaded(false);
      setImageError(false);
      const img = new Image();
      img.onload = () => setImageLoaded(true);
      img.onerror = () => setImageError(true);
      img.src = baseAssetUrl;
    }
  }, [tileImageUrl, baseAssetUrl, getCachedImage]);
  
  const terrainStyle: React.CSSProperties = {
    position: 'absolute',
    left: `${isoPos.x}px`,
    top: `${isoPos.y}px`,
    width: `${TILE_WIDTH}px`,
    height: `${TILE_HEIGHT}px`,
    zIndex: getTerrainZIndex(gridX, gridY, gridSize), // Use proper z-index calculation
    transform: 'translate(-50%, -50%)', // Center the tile
  };
  
  // Determine fallback color based on terrain type
  const getFallbackColor = () => {
    if (isAtMapEdge) {
      // Dirt/rock at edges for transitions
      return 'linear-gradient(135deg, #a78b5a 0%, #8b6f47 50%, #6b5233 100%)';
    }
    // Pure grass for interior tiles (no paths, just solid grass)
    return 'linear-gradient(135deg, #86efac 0%, #4ade80 50%, #22c55e 100%)';
  };

  // For interior tiles, always use CSS fallback (pure grass)
  // For edge tiles, try to use extracted tile, fallback to CSS if needed
  const displayUrl = isAtMapEdge ? (tileImageUrl || baseAssetUrl) : null;
  if (!displayUrl || imageError || !isAtMapEdge) {
    // Use CSS fallback for interior tiles or if image failed
    return (
      <div
        style={terrainStyle}
        className={className}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            background: getFallbackColor(),
            borderRadius: '2px',
            border: '1px solid rgba(0,0,0,0.1)', // Add subtle border for visibility
            boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.1)', // Add depth
          }}
        />
      </div>
    );
  }

  return (
    <div
      style={terrainStyle}
      className={className}
    >
      {imageLoaded && displayUrl && (
        <img
          src={displayUrl}
          alt={`${terrainType} terrain`}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            imageRendering: 'pixelated', // For pixel art
            userSelect: 'none',
            WebkitUserDrag: 'none',
          } as React.CSSProperties}
          draggable={false}
          loading="lazy"
        />
      )}
      {!imageLoaded && (
        <div
          style={{
            width: '100%',
            height: '100%',
            background: getFallbackColor(),
            borderRadius: '2px',
            opacity: 0.7,
          }}
        />
      )}
    </div>
  );
};

export default IsometricTerrain;

