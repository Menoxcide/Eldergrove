'use client'

import React, { useState, useEffect, useMemo } from 'react';
import { Road } from '@/stores/useRoadsStore';
import { gridToIsometric, TILE_WIDTH, TILE_HEIGHT, getZIndex } from '@/lib/isometricUtils';
import { useAssetStore } from '@/stores/useAssetStore';

interface RoadTileProps {
  road: Road | null;
  gridX?: number;
  gridY?: number;
  isPreview?: boolean;
  className?: string;
  useIsometric?: boolean; // Toggle between isometric and grid-based rendering
}

const RoadTile: React.FC<RoadTileProps> = ({ 
  road, 
  gridX,
  gridY,
  isPreview = false,
  className = '',
  useIsometric = false,
}) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);
  const getRoadAssetUrl = useAssetStore((state) => state.getRoadAssetUrl);
  
  if (!road && !isPreview) return null;

  const roadType = road?.road_type || 'straight_h';
  const assetUrl = getRoadAssetUrl(roadType);
  
  // Calculate isometric position if using isometric rendering (memoized)
  const isoPos = useMemo(() => {
    return useIsometric && gridX !== undefined && gridY !== undefined
      ? gridToIsometric(gridX, gridY)
      : null;
  }, [useIsometric, gridX, gridY]);
  
  const zIndex = useMemo(() => {
    return useIsometric && gridX !== undefined && gridY !== undefined
      ? getZIndex(gridX, gridY)
      : 1;
  }, [useIsometric, gridX, gridY]);

  const getCachedImage = useAssetStore((state) => state.getCachedImage);
  
  useEffect(() => {
    if (assetUrl) {
      // Check cache first
      const cached = getCachedImage(assetUrl);
      if (cached) {
        setImageLoaded(true);
        setImageError(false);
        return;
      }
      
      setImageLoaded(false);
      setImageError(false);
      
      // Preload image
      const img = new Image();
      img.onload = () => setImageLoaded(true);
      img.onerror = () => setImageError(true);
      img.src = assetUrl;
    }
  }, [assetUrl, getCachedImage]);

  const getRoadStyle = (): React.CSSProperties => {
    if (useIsometric && isoPos) {
      return {
        position: 'absolute',
        left: `${isoPos.x}px`,
        top: `${isoPos.y}px`,
        width: `${TILE_WIDTH}px`,
        height: `${TILE_HEIGHT}px`,
        zIndex: zIndex,
        opacity: isPreview ? 0.5 : 1,
        transform: 'translate(-50%, -50%)',
        pointerEvents: 'none',
      };
    }
    
    // Grid-based rendering (original)
    const baseStyle: React.CSSProperties = {
      width: '100%',
      height: '100%',
      position: 'relative',
      backgroundColor: '#4A4A4A',
      opacity: isPreview ? 0.5 : 1,
      border: isPreview ? '1px dashed rgba(255,255,255,0.3)' : 'none',
    };

    return baseStyle;
  };

  const getRoadPattern = () => {
    if (!road && isPreview) {
      // Preview: simple gray rectangle
      return (
        <div className="w-full h-full bg-gray-600"></div>
      );
    }

    if (!road) return null;

    const roadType = road.road_type;

    // Base road color with texture
    const baseRoad = (
      <div 
        className="absolute inset-0"
        style={{
          background: 'linear-gradient(90deg, #5A5A5A 0%, #4A4A4A 50%, #5A5A5A 100%)',
          backgroundSize: '20px 20px',
        }}
      />
    );

    // Road markings (yellow lines)
    const getMarkings = () => {
      switch (roadType) {
        case 'straight_h':
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
            </>
          );
        case 'straight_v':
          return (
            <>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 'corner_ne':
          return (
            <>
              <div className="absolute top-1/2 left-0 right-1/2 h-0.5 bg-yellow-400"></div>
              <div className="absolute left-1/2 top-0 bottom-1/2 w-0.5 bg-yellow-400"></div>
            </>
          );
        case 'corner_nw':
          return (
            <>
              <div className="absolute top-1/2 left-1/2 right-0 h-0.5 bg-yellow-400"></div>
              <div className="absolute left-1/2 top-0 bottom-1/2 w-0.5 bg-yellow-400"></div>
            </>
          );
        case 'corner_se':
          return (
            <>
              <div className="absolute top-1/2 left-0 right-1/2 h-0.5 bg-yellow-400"></div>
              <div className="absolute left-1/2 top-1/2 bottom-0 w-0.5 bg-yellow-400"></div>
            </>
          );
        case 'corner_sw':
          return (
            <>
              <div className="absolute top-1/2 left-1/2 right-0 h-0.5 bg-yellow-400"></div>
              <div className="absolute left-1/2 top-1/2 bottom-0 w-0.5 bg-yellow-400"></div>
            </>
          );
        case 'intersection':
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_n':
          // T-junction facing north: connects south, east, west (no north)
          return (
            <>
              <div className="absolute left-1/2 top-1/2 bottom-0 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_s':
          // T-junction facing south: connects north, east, west (no south)
          return (
            <>
              <div className="absolute left-1/2 top-0 bottom-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_e':
          // T-junction facing east: connects north, south, west (no east)
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute left-0 right-1/2 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_w':
          // T-junction facing west: connects north, south, east (no west)
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute left-1/2 right-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        default:
          return null;
      }
    };

    return (
      <>
        {baseRoad}
        {getMarkings()}
      </>
    );
  };

  // Use isometric sprite if available and loaded
  if (useIsometric && assetUrl && imageLoaded && !imageError) {
    return (
      <div 
        style={getRoadStyle()}
        className={className}
      >
          <img
            src={assetUrl}
            alt={`${roadType} road`}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'cover',
              imageRendering: 'pixelated',
              userSelect: 'none',
              WebkitUserDrag: 'none',
            } as React.CSSProperties}
            draggable={false}
            loading="lazy"
          />
        {isPreview && (
          <div
            style={{
              position: 'absolute',
              inset: 0,
              border: '2px dashed rgba(255,255,255,0.6)',
              pointerEvents: 'none',
            }}
          />
        )}
      </div>
    );
  }

  // Fallback to CSS-based rendering
  return (
    <div 
      style={getRoadStyle()}
      className={className}
    >
      {getRoadPattern()}
    </div>
  );
};

export default RoadTile;

