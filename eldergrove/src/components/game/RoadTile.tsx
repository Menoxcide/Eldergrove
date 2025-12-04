'use client'

import React from 'react';
import { Road } from '@/stores/useRoadsStore';

interface RoadTileProps {
  road: Road | null;
  isPreview?: boolean;
  className?: string;
}

const RoadTile: React.FC<RoadTileProps> = ({ 
  road, 
  isPreview = false,
  className = ''
}) => {
  if (!road && !isPreview) return null;

  const getRoadStyle = (): React.CSSProperties => {
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
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_s':
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_e':
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
            </>
          );
        case 't_w':
          return (
            <>
              <div className="absolute inset-y-0 left-1/2 w-0.5 bg-yellow-400 transform -translate-x-1/2"></div>
              <div className="absolute inset-x-0 top-1/2 h-0.5 bg-yellow-400 transform -translate-y-1/2"></div>
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

