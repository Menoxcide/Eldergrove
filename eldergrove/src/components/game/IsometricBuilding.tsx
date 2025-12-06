'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { BuildingType } from '@/stores/useCityStore';
import { getBuildingAsset } from '@/config/isometricAssets';
import { useAssetStore } from '@/stores/useAssetStore';
import { gridToIsometric, getZIndex, getIsometricBoundingBox, TILE_WIDTH, TILE_HEIGHT } from '@/lib/isometricUtils';
import { getBuildingIcon, getCategoryColor } from '@/lib/buildingIcons';

interface IsometricBuildingProps {
  buildingType: BuildingType;
  gridX: number;
  gridY: number;
  level?: number;
  isPreview?: boolean;
  className?: string;
  onClick?: () => void;
  onMouseEnter?: () => void;
  onMouseLeave?: () => void;
}

const IsometricBuilding: React.FC<IsometricBuildingProps> = ({
  buildingType,
  gridX,
  gridY,
  level = 1,
  isPreview = false,
  className = '',
  onClick,
  onMouseEnter,
  onMouseLeave,
}) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
  const getBuildingAssetUrl = useAssetStore((state) => state.getBuildingAssetUrl);
  
  const assetConfig = getBuildingAsset(buildingType.building_type);
  const assetUrl = getBuildingAssetUrl(buildingType.building_type);
  const iconConfig = getBuildingIcon(buildingType.building_type);
  const categoryColor = getCategoryColor(buildingType.category);
  
  // Calculate isometric position
  const isoPos = useMemo(() => gridToIsometric(gridX, gridY), [gridX, gridY]);
  const zIndex = useMemo(() => getZIndex(gridX, gridY), [gridX, gridY]);
  
  // Calculate bounding box for multi-tile buildings
  const boundingBox = useMemo(() => getIsometricBoundingBox(
    gridX,
    gridY,
    buildingType.size_x,
    buildingType.size_y
  ), [gridX, gridY, buildingType.size_x, buildingType.size_y]);
  
  // Calculate actual display size (accounting for isometric perspective)
  const displayWidth = boundingBox.width;
  const displayHeight = boundingBox.height;
  
  // Image caching and preloading
  useEffect(() => {
    if (assetUrl) {
      // Check if image is already cached
      const img = new Image();
      img.onload = () => {
        setImageLoaded(true);
        setImageError(false);
      };
      img.onerror = () => {
        setImageError(true);
        setImageLoaded(false);
      };
      
      // Set src to trigger load (browser will use cache if available)
      img.src = assetUrl;
    } else {
      setImageLoaded(false);
      setImageError(false);
    }
  }, [assetUrl]);
  
  // Fallback to CSS-based rendering if no asset URL
  const useFallback = !assetUrl || imageError;
  
  const buildingStyle: React.CSSProperties = {
    position: 'absolute',
    left: `${isoPos.x}px`,
    top: `${isoPos.y}px`,
    width: `${displayWidth}px`,
    height: `${displayHeight}px`,
    zIndex: zIndex + (isPreview ? 1000 : 0),
    opacity: isPreview ? 0.65 : 1,
    pointerEvents: onClick || onMouseEnter || onMouseLeave ? 'auto' : 'none',
    cursor: onClick ? 'pointer' : 'default',
    transform: `translate(-50%, -50%) ${isHovered && !isPreview ? 'scale(1.05)' : 'scale(1)'}`,
    transition: isPreview ? 'none' : 'opacity 0.2s ease, transform 0.2s ease',
    filter: isHovered && !isPreview ? 'brightness(1.1)' : 'brightness(1)',
  };
  
  const handleMouseEnter = () => {
    setIsHovered(true);
    onMouseEnter?.();
  };
  
  const handleMouseLeave = () => {
    setIsHovered(false);
    onMouseLeave?.();
  };
  
  if (useFallback) {
    // Fallback to CSS-based building visualization
    return (
      <div
        style={buildingStyle}
        className={className}
        onClick={onClick}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
      >
        <div
          style={{
            width: '100%',
            height: '100%',
            backgroundColor: categoryColor,
            borderRadius: '4px',
            border: isPreview ? '2px dashed rgba(255,255,255,0.6)' : '2px solid rgba(0,0,0,0.3)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: '24px',
            boxShadow: '0 4px 8px rgba(0,0,0,0.3)',
            position: 'relative',
          }}
        >
          {/* Building icon */}
          <div style={{ fontSize: '32px', marginBottom: '4px' }}>
            {iconConfig?.icon || buildingType.name.charAt(0)}
          </div>
          
          {/* Category badge */}
          {iconConfig && (
            <div
              style={{
                position: 'absolute',
                top: '2px',
                left: '2px',
                backgroundColor: iconConfig.badgeColor,
                color: '#fff',
                fontSize: '10px',
                fontWeight: 'bold',
                padding: '2px 4px',
                borderRadius: '3px',
                display: 'flex',
                alignItems: 'center',
                gap: '2px',
                boxShadow: '0 2px 4px rgba(0,0,0,0.3)',
              }}
            >
              <span>{iconConfig.categoryIcon}</span>
            </div>
          )}
          
          {/* Production/Function indicator */}
          {iconConfig && (iconConfig.productionIcon || iconConfig.functionIcon) && (
            <div
              style={{
                position: 'absolute',
                bottom: '2px',
                right: '2px',
                backgroundColor: 'rgba(0, 0, 0, 0.7)',
                color: '#fff',
                fontSize: '12px',
                padding: '2px 4px',
                borderRadius: '3px',
                display: 'flex',
                alignItems: 'center',
                gap: '2px',
              }}
            >
              <span>{iconConfig.productionIcon || iconConfig.functionIcon}</span>
            </div>
          )}
        </div>
        {level > 1 && !isPreview && (
          <div
            style={{
              position: 'absolute',
              top: '4px',
              right: '4px',
              backgroundColor: 'rgba(255, 215, 0, 0.9)',
              color: '#000',
              fontSize: '10px',
              fontWeight: 'bold',
              padding: '2px 4px',
              borderRadius: '4px',
              zIndex: 20,
              boxShadow: '0 2px 4px rgba(0,0,0,0.3)',
            }}
          >
            L{level}
          </div>
        )}
      </div>
    );
  }
  
  return (
    <div
      style={buildingStyle}
      className={className}
      onClick={onClick}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {!imageLoaded && (
        <div
          style={{
            width: '100%',
            height: '100%',
            backgroundColor: categoryColor + '40',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: '12px',
            color: '#666',
            borderRadius: '4px',
            border: '2px solid ' + categoryColor,
          }}
        >
          {iconConfig && (
            <div style={{ fontSize: '24px', marginBottom: '4px' }}>
              {iconConfig.icon}
            </div>
          )}
          <div>Loading...</div>
        </div>
      )}
      {imageLoaded && assetUrl && (
        <>
          <img
            src={assetUrl}
            alt={buildingType.name}
            style={{
              width: '100%',
              height: '100%',
              objectFit: 'contain',
              imageRendering: 'pixelated', // For pixel art
              userSelect: 'none',
              WebkitUserDrag: 'none',
            } as React.CSSProperties}
            draggable={false}
            loading="lazy" // Lazy load optimization
          />
          
          {/* Category badge overlay */}
          {iconConfig && (
            <div
              style={{
                position: 'absolute',
                top: '2px',
                left: '2px',
                backgroundColor: iconConfig.badgeColor + 'E6', // 90% opacity
                color: '#fff',
                fontSize: '10px',
                fontWeight: 'bold',
                padding: '2px 5px',
                borderRadius: '4px',
                display: 'flex',
                alignItems: 'center',
                gap: '3px',
                boxShadow: '0 2px 4px rgba(0,0,0,0.4)',
                zIndex: 15,
                backdropFilter: 'blur(4px)',
              }}
              title={buildingType.category === 'factory' ? 'Factory' : buildingType.category === 'community' ? 'Community' : 'Decoration'}
            >
              <span>{iconConfig.categoryIcon}</span>
            </div>
          )}
          
          {/* Production/Function indicator overlay */}
          {iconConfig && (iconConfig.productionIcon || iconConfig.functionIcon) && (
            <div
              style={{
                position: 'absolute',
                bottom: '2px',
                right: '2px',
                backgroundColor: 'rgba(0, 0, 0, 0.75)',
                color: '#fff',
                fontSize: '11px',
                padding: '3px 5px',
                borderRadius: '4px',
                display: 'flex',
                alignItems: 'center',
                gap: '3px',
                zIndex: 15,
                backdropFilter: 'blur(4px)',
                boxShadow: '0 2px 4px rgba(0,0,0,0.4)',
              }}
              title={
                iconConfig.productionIcon
                  ? `Produces: ${buildingType.name}`
                  : iconConfig.functionIcon
                  ? `Provides: ${buildingType.provides_population} population`
                  : ''
              }
            >
              <span>{iconConfig.productionIcon || iconConfig.functionIcon}</span>
            </div>
          )}
          
          {/* Level badge */}
          {level > 1 && !isPreview && (
            <div
              style={{
                position: 'absolute',
                top: '4px',
                right: '4px',
                background: 'linear-gradient(135deg, #FFD700 0%, #FFA500 100%)',
                color: '#000',
                fontSize: '10px',
                fontWeight: 'bold',
                padding: '3px 6px',
                borderRadius: '4px',
                zIndex: 20,
                boxShadow: '0 2px 6px rgba(255, 215, 0, 0.5)',
                border: '1px solid rgba(255, 200, 0, 0.8)',
              }}
            >
              L{level}
            </div>
          )}
          
          {/* Hover glow effect */}
          {isHovered && !isPreview && (
            <div
              style={{
                position: 'absolute',
                inset: '-2px',
                borderRadius: '6px',
                background: `linear-gradient(135deg, ${categoryColor}40, ${categoryColor}20)`,
                zIndex: -1,
                pointerEvents: 'none',
                filter: 'blur(4px)',
              }}
            />
          )}
        </>
      )}
      {isPreview && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            border: '2px dashed rgba(255,255,255,0.6)',
            pointerEvents: 'none',
            borderRadius: '4px',
            zIndex: 25,
          }}
        />
      )}
    </div>
  );
};

export default IsometricBuilding;

