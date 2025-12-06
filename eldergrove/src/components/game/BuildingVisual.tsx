'use client'

import React, { useState, useEffect } from 'react';
import { BuildingType } from '@/stores/useCityStore';
import { useAssetStore } from '@/stores/useAssetStore';
import { getBuildingAsset } from '@/config/isometricAssets';
import { getBuildingIcon, getCategoryColor } from '@/lib/buildingIcons';

interface BuildingVisualProps {
  buildingType: BuildingType;
  level?: number;
  size?: { width: number; height: number };
  isPreview?: boolean;
  className?: string;
  useIsometric?: boolean; // Toggle between isometric sprites and CSS rendering
}

const BuildingVisual: React.FC<BuildingVisualProps> = ({ 
  buildingType, 
  level = 1,
  size,
  isPreview = false,
  className = '',
  useIsometric = false,
}) => {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState(false);
  const getBuildingAssetUrl = useAssetStore((state) => state.getBuildingAssetUrl);
  const getCachedImage = useAssetStore((state) => state.getCachedImage);
  
  const assetConfig = getBuildingAsset(buildingType.building_type);
  const assetUrl = useIsometric ? getBuildingAssetUrl(buildingType.building_type) : null;
  const iconConfig = getBuildingIcon(buildingType.building_type);
  const categoryColor = getCategoryColor(buildingType.category);
  
  useEffect(() => {
    if (assetUrl && useIsometric) {
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
  }, [assetUrl, useIsometric, getCachedImage]);
  
  // Use isometric sprite if available and enabled
  if (useIsometric && assetUrl && imageLoaded && !imageError) {
    const displayWidth = size?.width || assetConfig?.width || 64;
    const displayHeight = size?.height || assetConfig?.height || 64;
    
    return (
      <div 
        style={{
          width: `${displayWidth}px`,
          height: `${displayHeight}px`,
          position: 'relative',
          opacity: isPreview ? 0.65 : 1,
        }}
        className={className}
      >
        <img
          src={assetUrl}
          alt={buildingType.name}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            imageRendering: 'pixelated',
            userSelect: 'none',
            WebkitUserDrag: 'none',
          } as React.CSSProperties}
          draggable={false}
          loading="lazy"
        />
        
        {/* Category badge overlay */}
        {iconConfig && (
          <div
            className="absolute top-0 left-0 text-xs font-bold px-1.5 py-0.5 rounded-br-lg shadow-lg z-20"
            style={{
              backgroundColor: iconConfig.badgeColor + 'E6',
              color: '#fff',
              fontSize: '9px',
              display: 'flex',
              alignItems: 'center',
              gap: '2px',
            }}
            title={buildingType.category === 'factory' ? 'Factory' : buildingType.category === 'community' ? 'Community' : 'Decoration'}
          >
            <span>{iconConfig.categoryIcon}</span>
          </div>
        )}
        
        {/* Production/Function indicator */}
        {iconConfig && (iconConfig.productionIcon || iconConfig.functionIcon) && (
          <div
            className="absolute bottom-0 right-0 text-xs px-1.5 py-0.5 rounded-tl-lg z-20"
            style={{
              backgroundColor: 'rgba(0, 0, 0, 0.75)',
              color: '#fff',
              fontSize: '10px',
              display: 'flex',
              alignItems: 'center',
              gap: '2px',
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
        
        {level > 1 && !isPreview && (
          <div className="absolute top-0 right-0 bg-gradient-to-br from-yellow-400 to-yellow-600 text-yellow-900 text-xs font-bold px-1.5 py-0.5 rounded-bl-lg border-b-2 border-l-2 border-yellow-700 shadow-lg z-20">
            L{level}
          </div>
        )}
        {isPreview && (
          <div className="absolute inset-0 border-2 border-dashed border-white/60 pointer-events-none" />
        )}
      </div>
    );
  }
  const getBuildingStyle = () => {
    const baseStyle: React.CSSProperties = {
      width: size?.width ? `${size.width}px` : '100%',
      height: size?.height ? `${size.height}px` : '100%',
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: '6px',
      boxShadow: isPreview 
        ? '0 0 12px rgba(0,0,0,0.4)' 
        : '0 4px 12px rgba(0,0,0,0.5), inset 0 2px 4px rgba(255,255,255,0.15), inset 0 -2px 4px rgba(0,0,0,0.2)',
      border: isPreview 
        ? '2px dashed rgba(255,255,255,0.6)' 
        : '3px solid',
      opacity: isPreview ? 0.65 : 1,
      transition: 'all 0.3s ease',
      overflow: 'hidden',
    };

    // Category-based colors with enhanced gradients
    if (buildingType.category === 'factory') {
      baseStyle.background = `linear-gradient(135deg, #6B3410 0%, #8B4513 30%, #A0522D 50%, #8B4513 70%, #6B3410 100%)`;
      baseStyle.borderColor = isPreview ? 'rgba(139, 69, 19, 0.6)' : 'rgba(80, 40, 10, 0.9)';
    } else if (buildingType.category === 'community') {
      baseStyle.background = `linear-gradient(135deg, #1E3A8A 0%, #2563EB 30%, #3B82F6 50%, #2563EB 70%, #1E3A8A 100%)`;
      baseStyle.borderColor = isPreview ? 'rgba(37, 99, 235, 0.6)' : 'rgba(20, 50, 150, 0.9)';
    } else {
      // decoration
      baseStyle.background = `linear-gradient(135deg, #65A30D 0%, #84CC16 30%, #A3E635 50%, #84CC16 70%, #65A30D 100%)`;
      baseStyle.borderColor = isPreview ? 'rgba(132, 204, 22, 0.6)' : 'rgba(80, 150, 20, 0.9)';
    }

    return baseStyle;
  };

  const getBuildingIconEmoji = () => {
    // Use icon config if available, otherwise fallback
    return iconConfig?.icon || '🏠';
  };

  const getBuildingDetails = () => {
    // Add enhanced visual details based on building type
    if (buildingType.building_type === 'town_hall') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-1/2 h-1/3 bg-gradient-to-b from-yellow-300 to-yellow-500 rounded-t-lg border-2 border-yellow-600 shadow-inner">
            <div className="w-full h-1/3 bg-yellow-600"></div>
          </div>
          <div className="w-full h-2/3 bg-gradient-to-b from-blue-500 to-blue-700 rounded-b-lg border-t-2 border-blue-800">
            <div className="absolute bottom-0 left-0 right-0 h-1/4 bg-blue-800"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'school') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-3/4 h-1/4 bg-gradient-to-b from-red-400 to-red-600 rounded-t-lg border-b-2 border-red-700"></div>
          <div className="w-full h-3/4 bg-gradient-to-b from-white to-gray-100 rounded-b-lg border-t-2 border-gray-400">
            <div className="absolute top-2 left-2 right-2 h-1 bg-gray-300"></div>
            <div className="absolute top-4 left-2 right-2 h-1 bg-gray-300"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'hospital') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-1/3 h-1/3 bg-gradient-to-br from-red-500 to-red-700 rounded-full border-2 border-red-800 shadow-lg"></div>
          <div className="w-full h-2/3 bg-gradient-to-b from-white to-gray-50 rounded-b-lg border-t-2 border-gray-300">
            <div className="absolute bottom-2 left-1/4 right-1/4 h-1/4 bg-blue-200 rounded"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'rune_bakery') {
      return (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-2/3 h-2/3 bg-gradient-to-br from-amber-200 via-amber-300 to-amber-400 rounded-lg border-3 border-amber-600 shadow-inner">
            <div className="absolute top-1/4 left-1/4 w-1/2 h-1/2 bg-amber-500 rounded opacity-50"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'potion_workshop') {
      return (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-1/2 h-3/4 bg-gradient-to-br from-purple-300 via-purple-400 to-purple-500 rounded-lg border-3 border-purple-700 shadow-inner">
            <div className="absolute top-1/3 left-1/3 w-1/3 h-1/3 bg-purple-600 rounded-full opacity-60"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'enchanting_lab') {
      return (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-1/2 h-3/4 bg-gradient-to-br from-indigo-300 via-indigo-400 to-indigo-600 rounded-lg border-3 border-indigo-800 shadow-inner">
            <div className="absolute top-1/4 left-1/4 w-1/2 h-1/2 bg-indigo-500 rounded-full opacity-40"></div>
            <div className="absolute top-1/2 left-1/3 w-1/3 h-1/4 bg-indigo-700 rounded"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'kitchen') {
      return (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-2/3 h-2/3 bg-gradient-to-br from-orange-300 via-orange-400 to-orange-600 rounded-lg border-3 border-orange-700 shadow-inner">
            <div className="absolute top-1/3 left-1/4 w-1/2 h-1/3 bg-orange-500 rounded"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'cinema') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-3/4 h-1/4 bg-gradient-to-b from-gray-600 to-gray-800 rounded-t-lg"></div>
          <div className="w-full h-3/4 bg-gradient-to-b from-gray-800 to-gray-900 rounded-b-lg border-t-2 border-gray-700">
            <div className="absolute top-1/3 left-1/4 right-1/4 h-1/3 bg-gray-700 rounded"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'fountain') {
      return (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-3/4 h-3/4 bg-gradient-to-br from-blue-300 via-blue-400 to-blue-600 rounded-full border-3 border-blue-700 shadow-inner">
            <div className="absolute top-1/4 left-1/4 w-1/2 h-1/2 bg-blue-500 rounded-full opacity-50"></div>
            <div className="absolute bottom-0 left-0 right-0 h-1/4 bg-blue-800 rounded-b-full"></div>
          </div>
        </div>
      );
    }
    if (buildingType.building_type === 'statue') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-1/3 h-1/3 bg-gradient-to-b from-gray-400 to-gray-600 rounded-t-full"></div>
          <div className="w-1/2 h-1/2 bg-gradient-to-b from-gray-500 to-gray-700 rounded-b-lg"></div>
          <div className="w-2/3 h-1/6 bg-gray-600 rounded"></div>
        </div>
      );
    }
    if (buildingType.building_type === 'tree') {
      return (
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <div className="w-2/3 h-2/3 bg-gradient-to-br from-green-500 via-green-600 to-green-800 rounded-full shadow-lg">
            <div className="absolute top-1/4 left-1/4 w-1/2 h-1/2 bg-green-400 rounded-full opacity-40"></div>
          </div>
          <div className="w-1/4 h-1/3 bg-gradient-to-b from-amber-700 to-amber-900 rounded"></div>
        </div>
      );
    }
    return null;
  };

  return (
    <div 
      style={getBuildingStyle()}
      className={`${className} ${!isPreview ? 'hover:scale-105 hover:shadow-xl' : ''} group`}
    >
      {getBuildingDetails()}
      <span 
        className="text-lg md:text-xl lg:text-2xl z-10 relative transition-transform group-hover:scale-110"
        style={{ textShadow: '0 2px 4px rgba(0,0,0,0.6), 0 0 8px rgba(255,255,255,0.2)' }}
      >
        {getBuildingIconEmoji()}
      </span>
      {level > 1 && !isPreview && (
        <div className="absolute top-0 right-0 bg-gradient-to-br from-yellow-400 to-yellow-600 text-yellow-900 text-xs font-bold px-1.5 py-0.5 rounded-bl-lg border-b-2 border-l-2 border-yellow-700 shadow-lg z-20">
          L{level}
        </div>
      )}
      {!isPreview && (
        <div className="absolute inset-0 bg-gradient-to-t from-black/10 to-transparent pointer-events-none rounded-lg"></div>
      )}
    </div>
  );
};

export default BuildingVisual;

