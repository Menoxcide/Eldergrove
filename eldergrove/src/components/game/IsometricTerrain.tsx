'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { gridToIsometric, TILE_WIDTH, TILE_HEIGHT } from '@/lib/isometricUtils';
import { useAssetStore } from '@/stores/useAssetStore';

interface IsometricTerrainProps {
  gridX: number;
  gridY: number;
  terrainType?: string;
  className?: string;
}

const IsometricTerrain: React.FC<IsometricTerrainProps> = ({
  gridX,
  gridY,
  terrainType = 'grass',
  className = '',
}) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);
  const getTerrainAssetUrl = useAssetStore((state) => state.getTerrainAssetUrl);
  const getCachedImage = useAssetStore((state) => state.getCachedImage);
  const assetUrl = getTerrainAssetUrl(terrainType);
  
  // Calculate isometric position (memoized)
  const isoPos = useMemo(() => gridToIsometric(gridX, gridY), [gridX, gridY]);
  
  // Check cache first, then load
  useEffect(() => {
    if (assetUrl) {
      const cached = getCachedImage(assetUrl);
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
      img.src = assetUrl;
    }
  }, [assetUrl, getCachedImage]);
  
  const terrainStyle: React.CSSProperties = {
    position: 'absolute',
    left: `${isoPos.x}px`,
    top: `${isoPos.y}px`,
    width: `${TILE_WIDTH}px`,
    height: `${TILE_HEIGHT}px`,
    zIndex: 0, // Terrain is always at the bottom
    transform: 'translate(-50%, -50%)', // Center the tile
  };
  
  // Fallback to CSS gradient if no asset URL or error
  if (!assetUrl || imageError) {
    return (
      <div
        style={terrainStyle}
        className={className}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            background: 'linear-gradient(135deg, #86efac 0%, #4ade80 50%, #22c55e 100%)',
            borderRadius: '2px',
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
      {imageLoaded && (
        <img
          src={assetUrl}
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
            background: 'linear-gradient(135deg, #86efac 0%, #4ade80 50%, #22c55e 100%)',
            borderRadius: '2px',
            opacity: 0.7,
          }}
        />
      )}
    </div>
  );
};

export default IsometricTerrain;

