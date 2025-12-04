'use client'

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useCityStore, type Building, type BuildingType } from '@/stores/useCityStore';
import { useDecorationsStore, type Decoration, type DecorationType } from '@/stores/useDecorationsStore';
import { useRoadsStore, type Road } from '@/stores/useRoadsStore';
import BuildingVisual from '@/components/game/BuildingVisual';
import RoadTile from '@/components/game/RoadTile';
import Tooltip from '@/components/ui/Tooltip';
import { getBuildingTooltip, getActionTooltip } from '@/lib/tooltipUtils';

interface TownMapProps {
  loading?: boolean;
}

const TownMap: React.FC<TownMapProps> = ({ loading = false }) => {
  const { claimDailyReward, crystals, population, townSize, expandTown, getExpansionCost, fetchPlayerProfile, loading: playerLoading, level: playerLevel } = usePlayerStore();
  const { 
    buildings, 
    buildingTypes, 
    loading: buildingsLoading,
    fetchBuildings, 
    fetchBuildingTypes,
    placeBuilding,
    removeBuilding,
    subscribeToBuildings
  } = useCityStore();
  const {
    roads,
    loading: roadsLoading,
    fetchRoads,
    placeRoad,
    removeRoad,
    subscribeToRoads
  } = useRoadsStore();
  const [isClaiming, setIsClaiming] = useState(false);
  const [placementMode, setPlacementMode] = useState<'view' | 'place' | 'remove' | 'decorate' | 'roads'>('view');
  const [selectedBuildingType, setSelectedBuildingType] = useState<string | null>(null);
  const [selectedDecorationType, setSelectedDecorationType] = useState<string | null>(null);
  const [hoveredCell, setHoveredCell] = useState<{x: number, y: number} | null>(null);
  const [showExpansionModal, setShowExpansionModal] = useState(false);
  const [expansionCost, setExpansionCost] = useState<number>(0);
  const [selectedBuilding, setSelectedBuilding] = useState<Building | null>(null);
  const [showBuildingModal, setShowBuildingModal] = useState(false);
  
  // Zoom and pan state
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const gridRef = useRef<HTMLDivElement>(null);
  
  const router = useRouter();
  
  const {
    decorations,
    decorationTypes,
    fetchDecorations,
    fetchDecorationTypes,
    placeDecoration,
    removeDecoration,
    subscribeToDecorations
  } = useDecorationsStore();
  
  const GRID_SIZE = townSize || 10;

  useEffect(() => {
    fetchPlayerProfile();
    fetchBuildings();
    fetchBuildingTypes();
    fetchDecorations();
    fetchDecorationTypes();
    fetchRoads();
    const unsubscribeBuildings = subscribeToBuildings();
    const unsubscribeDecorations = subscribeToDecorations();
    const unsubscribeRoads = subscribeToRoads();
    return () => {
      unsubscribeBuildings();
      unsubscribeDecorations();
      unsubscribeRoads();
    };
  }, [fetchPlayerProfile, fetchBuildings, fetchBuildingTypes, fetchDecorations, fetchDecorationTypes, fetchRoads, subscribeToBuildings, subscribeToDecorations, subscribeToRoads]);

  useEffect(() => {
    if (showExpansionModal) {
      getExpansionCost('all').then(setExpansionCost);
    }
  }, [showExpansionModal, getExpansionCost]);

  // Zoom and pan handlers
  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (e.ctrlKey || e.metaKey) {
      e.preventDefault();
      const delta = e.deltaY > 0 ? 0.9 : 1.1;
      setZoom(prev => Math.max(0.5, Math.min(3, prev * delta)));
    }
  }, []);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    if (e.button === 1 || (e.button === 0 && e.shiftKey)) {
      e.preventDefault();
      setIsDragging(true);
      setDragStart({ x: e.clientX - pan.x, y: e.clientY - pan.y });
    }
  }, [pan]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    if (isDragging) {
      setPan({
        x: e.clientX - dragStart.x,
        y: e.clientY - dragStart.y
      });
    }
  }, [isDragging, dragStart]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
  }, []);

  const resetView = () => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  };

  const getBuildingAtCell = (x: number, y: number): Building | null => {
    return buildings.find(b => {
      const buildingType = buildingTypes.find(bt => bt.building_type === b.building_type);
      if (!buildingType) return false;
      return x >= b.grid_x && x < b.grid_x + buildingType.size_x &&
             y >= b.grid_y && y < b.grid_y + buildingType.size_y;
    }) || null;
  };

  const getDecorationAtCell = (x: number, y: number): Decoration | null => {
    return decorations.find(d => {
      const decorationType = decorationTypes.find(dt => dt.decoration_type === d.decoration_type);
      if (!decorationType) return false;
      return x >= d.grid_x && x < d.grid_x + decorationType.size_x &&
             y >= d.grid_y && y < d.grid_y + decorationType.size_y;
    }) || null;
  };

  const getRoadAtCell = (x: number, y: number): Road | null => {
    return roads.find(r => r.grid_x === x && r.grid_y === y) || null;
  };

  const getCellArea = (row: number, col: number): { name: string; path: string; icon: string; building?: Building } | null => {
    // Check if there's a building here first
    const building = getBuildingAtCell(col, row);
    if (building) {
      const buildingType = buildingTypes.find(bt => bt.building_type === building.building_type);
      if (buildingType && col === building.grid_x && row === building.grid_y) {
        // Factory buildings navigate to factory page
        if (buildingType.category === 'factory') {
          return { 
            name: buildingType.name, 
            path: `/game/factory?building=${building.building_type}`, 
            icon: '🏭',
            building 
          };
        }
        // Community buildings and decorations show detail modal (path will be handled in click handler)
        return { 
          name: buildingType.name, 
          path: '#', 
          icon: buildingType.category === 'community' ? '🏛️' : '🎨',
          building 
        };
      }
    }

    // Legacy navigation areas (only if no building)
    if (row < 3 && col < 3) {
      return { name: 'Farm', path: '/game/farm', icon: '🌱' };
    }
    if (row < 3 && col > 6) {
      return { name: 'Factory', path: '/game/factory', icon: '⚙️' };
    }
    if (row > 6 && col < 3) {
      return { name: 'Shop', path: '/game/shop', icon: '🏪' };
    }
    if (row >= 3 && row < 7 && col < 3) {
      return { name: 'Skyport', path: '/game/skyport', icon: '✈️' };
    }
    if (row >= 3 && row < 7 && col > 6) {
      return { name: 'Mine', path: '/game/mine', icon: '⛏️' };
    }
    if (row > 6 && col >= 3 && col < 7) {
      return { name: 'Zoo', path: '/game/zoo', icon: '🐾' };
    }
    if (row > 6 && col > 6) {
      return { name: 'Coven', path: '/game/coven', icon: '👥' };
    }
    return null;
  };

  const handleCellClick = async (row: number, col: number) => {
    if (placementMode === 'place' && selectedBuildingType) {
      try {
        await placeBuilding(selectedBuildingType, col, row);
        setPlacementMode('view');
        setSelectedBuildingType(null);
      } catch (error) {
        // Error handled in store
      }
      return;
    }

    if (placementMode === 'decorate' && selectedDecorationType) {
      try {
        await placeDecoration(selectedDecorationType, col, row);
        setPlacementMode('view');
        setSelectedDecorationType(null);
      } catch (error) {
        // Error handled in store
      }
      return;
    }

    if (placementMode === 'roads') {
      const road = getRoadAtCell(col, row);
      if (road) {
        try {
          await removeRoad(col, row);
        } catch (error) {
          // Error handled in store
        }
      } else {
        try {
          await placeRoad(col, row);
        } catch (error) {
          // Error handled in store
        }
      }
      return;
    }

    if (placementMode === 'remove') {
      const building = getBuildingAtCell(col, row);
      if (building && col === building.grid_x && row === building.grid_y) {
        if (confirm('Remove this building?')) {
          await removeBuilding(building.id);
        }
        return;
      }
      const decoration = getDecorationAtCell(col, row);
      if (decoration && col === decoration.grid_x && row === decoration.grid_y) {
        if (confirm('Remove this decoration?')) {
          await removeDecoration(decoration.id);
        }
      }
      const road = getRoadAtCell(col, row);
      if (road) {
        if (confirm('Remove this road?')) {
          await removeRoad(col, row);
        }
      }
      return;
    }

    // Normal navigation - handle building clicks
    const area = getCellArea(row, col);
    if (area) {
      if (area.building && area.path === '#') {
        // Show building detail modal for community buildings and decorations
        setSelectedBuilding(area.building);
        setShowBuildingModal(true);
      } else if (area.path !== '#') {
        // Navigate to path (factory buildings or legacy areas)
        router.push(area.path);
      }
    }
  };
  
  const handleClaimReward = async () => {
    setIsClaiming(true);
    try {
      await claimDailyReward();
    } finally {
      setIsClaiming(false);
    }
  };

  const isCellOccupied = (x: number, y: number): boolean => {
    return getBuildingAtCell(x, y) !== null || getDecorationAtCell(x, y) !== null;
  };

  const canPlaceBuilding = (buildingType: BuildingType | null, x: number, y: number): boolean => {
    if (!buildingType) return false;
    
    // Check building limit
    if (buildingType.max_count !== null) {
      const currentCount = buildings.filter(b => b.building_type === buildingType.building_type).length;
      if (currentCount >= buildingType.max_count) {
        return false;
      }
    }
    
    // Check grid bounds and occupancy
    for (let dx = 0; dx < buildingType.size_x; dx++) {
      for (let dy = 0; dy < buildingType.size_y; dy++) {
        if (isCellOccupied(x + dx, y + dy)) return false;
        if (x + dx >= GRID_SIZE || y + dy >= GRID_SIZE) return false;
      }
    }
    
    // Check resources
    const hasCrystals = crystals >= buildingType.base_cost_crystals;
    const hasPopulation = (buildingType.population_required || 0) <= (population ?? 0);
    const hasLevel = (buildingType.level_required || 1) <= (playerLevel || 1);
    
    return hasCrystals && hasPopulation && hasLevel;
  };

  const canPlaceDecoration = (decorationType: DecorationType | null, x: number, y: number): boolean => {
    if (!decorationType) return false;
    for (let dx = 0; dx < decorationType.size_x; dx++) {
      for (let dy = 0; dy < decorationType.size_y; dy++) {
        if (isCellOccupied(x + dx, y + dy)) return false;
        if (x + dx >= GRID_SIZE || y + dy >= GRID_SIZE) return false;
      }
    }
    return crystals >= decorationType.cost_crystals;
  };

  const canPlaceRoad = (x: number, y: number): boolean => {
    // Roads can't be placed on buildings or decorations
    // Roads can be placed on existing roads (to update their type)
    // Check bounds
    if (x < 0 || x >= GRID_SIZE || y < 0 || y >= GRID_SIZE) return false;
    // Check if cell is occupied by building or decoration
    return !isCellOccupied(x, y);
  };

  if (loading || buildingsLoading || roadsLoading) {
    return (
      <div className="w-full max-w-4xl mx-auto p-6 bg-gradient-to-br from-emerald-900 via-green-900 to-amber-900 rounded-2xl shadow-2xl border border-emerald-500/30">
        <Skeleton className="w-full aspect-square rounded-xl" />
        <Skeleton className="h-6 w-3/4 mx-auto mt-4 rounded-lg" />
      </div>
    );
  }

  const selectedBuildingTypeData = buildingTypes.find(bt => bt.building_type === selectedBuildingType);
  const selectedDecorationTypeData = decorationTypes.find(dt => dt.decoration_type === selectedDecorationType);

  return (
    <div className="w-full max-w-7xl mx-auto p-4 md:p-6 bg-gradient-to-br from-emerald-900 via-green-900 to-amber-900 rounded-2xl shadow-2xl border border-emerald-500/30">
      {/* Top Controls Bar */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Tooltip content={getActionTooltip('Daily Reward', undefined, ['Claim your daily reward', 'Resets every 24 hours', 'Earn crystals, XP, and items'])} position="bottom">
          <button
            onClick={handleClaimReward}
            disabled={isClaiming}
            className={`px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all text-sm ${
              isClaiming 
                ? 'bg-gray-400 cursor-not-allowed' 
                : 'bg-yellow-500 hover:bg-yellow-400 text-gray-900'
            }`}
          >
            {isClaiming ? 'Claiming...' : 'Daily Reward'}
          </button>
        </Tooltip>
        
        <div className="flex gap-2 flex-wrap">
          <button
            onClick={() => {
              setPlacementMode(placementMode === 'place' ? 'view' : 'place');
              if (placementMode === 'place') {
                setSelectedBuildingType(null);
                setSelectedDecorationType(null);
              }
            }}
            className={`px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all text-sm ${
              placementMode === 'place' 
                ? 'bg-green-600 text-white shadow-lg' 
                : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
            }`}
          >
            {placementMode === 'place' ? '✓ Building' : 'Place Building'}
          </button>
          <button
            onClick={() => {
              setPlacementMode(placementMode === 'decorate' ? 'view' : 'decorate');
              if (placementMode === 'decorate') {
                setSelectedBuildingType(null);
                setSelectedDecorationType(null);
              }
            }}
            className={`px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all text-sm ${
              placementMode === 'decorate' 
                ? 'bg-pink-600 text-white shadow-lg' 
                : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
            }`}
          >
            {placementMode === 'decorate' ? '✓ Decorate' : 'Decorate'}
          </button>
          <button
            onClick={() => {
              setPlacementMode(placementMode === 'roads' ? 'view' : 'roads');
            }}
            className={`px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all text-sm ${
              placementMode === 'roads' 
                ? 'bg-gray-600 text-white shadow-lg' 
                : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
            }`}
          >
            {placementMode === 'roads' ? '✓ Roads' : 'Roads'}
          </button>
          <button
            onClick={() => {
              setPlacementMode(placementMode === 'remove' ? 'view' : 'remove');
            }}
            className={`px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all text-sm ${
              placementMode === 'remove' 
                ? 'bg-red-600 text-white shadow-lg' 
                : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
            }`}
          >
            {placementMode === 'remove' ? '✓ Remove' : 'Remove'}
          </button>
        </div>

        <Tooltip content={getActionTooltip('Expand Town', expansionCost, ['Increase town size', `Current: ${GRID_SIZE}x${GRID_SIZE}`, `New: ${GRID_SIZE + 5}x${GRID_SIZE + 5}`, 'More space for buildings'])} position="bottom">
          <button
            onClick={() => setShowExpansionModal(true)}
            className="px-3 py-1.5 md:px-4 md:py-2 rounded-lg font-semibold transition-all bg-purple-600 text-white hover:bg-purple-500 text-sm"
          >
            Expand
          </button>
        </Tooltip>

        <div className="ml-auto flex items-center gap-2 md:gap-3">
          <div className="flex items-center gap-1.5 md:gap-2 px-2 md:px-4 py-1.5 md:py-2 bg-slate-800/60 rounded-lg">
            <span className="text-lg md:text-xl">👥</span>
            <span className="text-white font-mono text-sm md:text-base">
              {playerLoading ? '...' : Number(population || 0).toLocaleString()}
            </span>
          </div>
          <div className="flex items-center gap-1.5 md:gap-2 px-2 md:px-4 py-1.5 md:py-2 bg-slate-800/60 rounded-lg">
            <span className="text-lg md:text-xl">💎</span>
            <span className="text-white font-mono text-sm md:text-base">
              {playerLoading ? '...' : Number(crystals || 0).toLocaleString()}
            </span>
          </div>
        </div>
      </div>

      <div className="flex flex-col lg:flex-row gap-4">
        {/* Building/Decoration Selection Panel */}
        {(placementMode === 'place' || placementMode === 'decorate') && (
          <div className="w-full lg:w-64 bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20 max-h-[500px] overflow-y-auto">
            {placementMode === 'place' ? (
              <>
                <h3 className="text-xl font-bold text-white mb-4">Select Building</h3>
                <div className="space-y-2">
                  {buildingTypes.map((bt) => {
                    const building = buildings.find(b => b.building_type === bt.building_type);
                    const currentCount = buildings.filter(b => b.building_type === bt.building_type).length;
                    const isAtLimit = bt.max_count !== null && currentCount >= bt.max_count;
                    const canAfford = crystals >= bt.base_cost_crystals;
                    const hasPopulation = (bt.population_required || 0) <= (population ?? 0);
                    const hasLevel = (bt.level_required || 1) <= (playerLevel || 1);
                    const isDisabled = isAtLimit || !canAfford || !hasPopulation || !hasLevel;
                    
                    return (
                      <Tooltip 
                        key={bt.building_type} 
                        content={getBuildingTooltip(bt, building?.level)} 
                        position="right"
                      >
                        <button
                          onClick={() => !isDisabled && setSelectedBuildingType(bt.building_type)}
                          disabled={isDisabled}
                          className={`w-full p-3 rounded-lg text-left transition-all ${
                            isDisabled
                              ? 'bg-slate-900/60 border-2 border-slate-700 opacity-50 cursor-not-allowed'
                              : selectedBuildingType === bt.building_type
                              ? 'bg-green-600 border-2 border-green-400 shadow-lg'
                              : 'bg-slate-800/60 hover:bg-slate-700/60 border-2 border-transparent'
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <BuildingVisual buildingType={bt} size={{ width: 40, height: 40 }} className="flex-shrink-0" />
                            <div className="flex-1 min-w-0">
                              <div className="text-white font-semibold text-sm">{bt.name}</div>
                              <div className="text-yellow-400 text-xs">💎 {bt.base_cost_crystals}</div>
                              <div className="flex items-center gap-2 text-xs flex-wrap">
                                <span className="text-slate-400">{bt.size_x}x{bt.size_y}</span>
                                {bt.max_count !== null && (
                                  <span className={`${isAtLimit ? 'text-red-400' : 'text-blue-400'}`}>
                                    {currentCount}/{bt.max_count}
                                  </span>
                                )}
                                {bt.provides_population > 0 && (
                                  <span className="text-green-400">+{bt.provides_population} 👥</span>
                                )}
                                {bt.population_required > 0 && (
                                  <span className={`${hasPopulation ? 'text-green-400' : 'text-red-400'}`}>
                                    Req {bt.population_required} 👥
                                  </span>
                                )}
                                {bt.level_required && bt.level_required > 1 && (
                                  <span className={`${hasLevel ? 'text-green-400' : 'text-red-400'}`}>
                                    Lv {bt.level_required}
                                  </span>
                                )}
                              </div>
                              {isAtLimit && (
                                <div className="text-red-400 text-xs mt-1">Limit reached</div>
                              )}
                            </div>
                          </div>
                        </button>
                      </Tooltip>
                    );
                  })}
                </div>
              </>
            ) : (
              <>
                <h3 className="text-xl font-bold text-white mb-4">Select Decoration</h3>
                <div className="space-y-2">
                  {decorationTypes.map((dt) => (
                    <button
                      key={dt.decoration_type}
                      onClick={() => setSelectedDecorationType(dt.decoration_type)}
                      className={`w-full p-3 rounded-lg text-left transition-all ${
                        selectedDecorationType === dt.decoration_type
                          ? 'bg-pink-600 border-2 border-pink-400 shadow-lg'
                          : 'bg-slate-800/60 hover:bg-slate-700/60 border-2 border-transparent'
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <span className="text-2xl">{dt.icon}</span>
                        <div className="flex-1">
                          <div className="text-white font-semibold text-sm">{dt.name}</div>
                          <div className="text-yellow-400 text-xs">💎 {dt.cost_crystals}</div>
                          <div className="text-slate-400 text-xs">{dt.size_x}x{dt.size_y}</div>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        )}

        {/* Town Grid Container */}
        <div className="flex-1 relative">
          {/* Zoom Controls */}
          <div className="absolute top-2 right-2 z-10 flex flex-col gap-2 bg-slate-800/80 rounded-lg p-2 backdrop-blur-sm">
            <button
              onClick={() => setZoom(prev => Math.min(3, prev + 0.25))}
              className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded text-sm font-semibold"
              disabled={zoom >= 3}
            >
              +
            </button>
            <span className="text-white text-xs text-center font-mono">{Math.round(zoom * 100)}%</span>
            <button
              onClick={() => setZoom(prev => Math.max(0.5, prev - 0.25))}
              className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded text-sm font-semibold"
              disabled={zoom <= 0.5}
            >
              −
            </button>
            <button
              onClick={resetView}
              className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded text-xs font-semibold mt-1"
            >
              Reset
            </button>
          </div>

          {/* Town Grid */}
          <div 
            className="relative w-full aspect-square bg-gradient-to-br from-green-100 via-green-200 to-emerald-300 p-2 rounded-xl shadow-inner border-4 border-green-600/50 overflow-hidden"
            onWheel={handleWheel}
            onMouseDown={handleMouseDown}
            onMouseMove={handleMouseMove}
            onMouseUp={handleMouseUp}
            onMouseLeave={handleMouseUp}
            ref={gridRef}
          >
            <div 
              className="w-full h-full grid gap-[1px] bg-black/10 rounded-lg"
              style={{
                gridTemplateColumns: `repeat(${GRID_SIZE}, 1fr)`,
                gridTemplateRows: `repeat(${GRID_SIZE}, 1fr)`,
                transform: `scale(${zoom}) translate(${pan.x / zoom}px, ${pan.y / zoom}px)`,
                transformOrigin: 'center center',
                transition: isDragging ? 'none' : 'transform 0.1s ease-out'
              }}
            >
              {Array.from({ length: GRID_SIZE }, (_, rowIndex) =>
                Array.from({ length: GRID_SIZE }, (_, colIndex) => {
                  const building = getBuildingAtCell(colIndex, rowIndex);
                  const isTopLeft = building && building.grid_x === colIndex && building.grid_y === rowIndex;
                  const decoration = getDecorationAtCell(colIndex, rowIndex);
                  const isDecorationTopLeft = decoration && decoration.grid_x === colIndex && decoration.grid_y === rowIndex;
                  const road = getRoadAtCell(colIndex, rowIndex);
                  const area = getCellArea(rowIndex, colIndex);
                  const isInteractive = area !== null && placementMode === 'view';
                  const isHovered = hoveredCell?.x === colIndex && hoveredCell?.y === rowIndex;
                  const canPlace = selectedBuildingTypeData && canPlaceBuilding(selectedBuildingTypeData, colIndex, rowIndex);
                  const canPlaceDeco = selectedDecorationTypeData && canPlaceDecoration(selectedDecorationTypeData, colIndex, rowIndex);
                  const canPlaceRoadHere = canPlaceRoad(colIndex, rowIndex);

                  // Show building preview
                  const showPreview = placementMode === 'place' && selectedBuildingTypeData && isHovered && canPlace;
                  const previewBuildingType = showPreview ? selectedBuildingTypeData : null;

                  let cellClass = 'aspect-square relative flex items-center justify-center transition-all duration-150 border ';
                  
                  // Terrain base styling - Township-inspired grass
                  if (road) {
                    cellClass += 'bg-gray-500/20 border-gray-600/30';
                  } else if (placementMode === 'place' && selectedBuildingTypeData) {
                    if (canPlace && isHovered) {
                      cellClass += 'bg-green-400/40 border-green-500 cursor-pointer';
                    } else if (!canPlace && isHovered) {
                      cellClass += 'bg-red-400/40 border-red-500 cursor-not-allowed';
                    } else {
                      cellClass += 'bg-green-200/30 border-green-300/30';
                    }
                  } else if (placementMode === 'decorate' && selectedDecorationTypeData) {
                    if (canPlaceDeco && isHovered) {
                      cellClass += 'bg-pink-400/40 border-pink-500 cursor-pointer';
                    } else if (!canPlaceDeco && isHovered) {
                      cellClass += 'bg-red-400/40 border-red-500 cursor-not-allowed';
                    } else {
                      cellClass += 'bg-green-200/30 border-green-300/30';
                    }
                  } else if (placementMode === 'roads') {
                    if (road) {
                      cellClass += isHovered ? 'bg-gray-500/70 border-gray-400 cursor-pointer ring-2 ring-gray-300' : 'bg-gray-500/30 border-gray-600/50';
                    } else if (canPlaceRoadHere) {
                      if (isHovered) {
                        cellClass += 'bg-gray-400/60 border-gray-500 cursor-pointer ring-2 ring-gray-300';
                      } else {
                        cellClass += 'bg-gray-300/30 border-gray-400/40';
                      }
                    } else {
                      // Can't place road here (occupied by building/decoration)
                      cellClass += isHovered ? 'bg-red-400/40 border-red-500 cursor-not-allowed' : 'bg-green-200/30 border-green-300/30';
                    }
                  } else if (placementMode === 'remove' && (building && isTopLeft || decoration && isDecorationTopLeft || road)) {
                    cellClass += isHovered ? 'bg-red-500/50 border-red-400 cursor-pointer' : 'bg-red-500/30 border-red-400/50 cursor-pointer';
                  } else if (isInteractive) {
                    cellClass += 'bg-green-300/50 hover:bg-green-400/60 hover:shadow-md border-green-400/40 cursor-pointer';
                  } else {
                    // Default grass terrain
                    cellClass += 'bg-gradient-to-br from-green-200 via-green-300 to-emerald-400 border-green-400/20';
                  }

                  const getCellTooltipContent = () => {
                    if (placementMode === 'place' && selectedBuildingTypeData) {
                      if (canPlace) {
                        return getBuildingTooltip(selectedBuildingTypeData);
                      } else {
                        return [
                          {
                            title: 'Cannot Place Here',
                            icon: '⚠️',
                            color: 'red' as const,
                            content: (
                              <div className="space-y-1 text-xs">
                                <p>• Cell is occupied or out of bounds</p>
                                <p>• Need {selectedBuildingTypeData.base_cost_crystals} crystals</p>
                                {selectedBuildingTypeData.population_required > 0 && (
                                  <p>• Need {selectedBuildingTypeData.population_required} population</p>
                                )}
                              </div>
                            ),
                          },
                        ];
                      }
                    } else if (placementMode === 'decorate' && selectedDecorationTypeData) {
                      if (canPlaceDeco) {
                        return [
                          {
                            title: selectedDecorationTypeData.name,
                            icon: selectedDecorationTypeData.icon || '🎨',
                            color: 'purple' as const,
                            content: (
                              <div className="space-y-2">
                                <div className="flex items-center justify-between">
                                  <span>Cost:</span>
                                  <span className="font-bold text-yellow-300">💎 {selectedDecorationTypeData.cost_crystals.toLocaleString()}</span>
                                </div>
                                <div className="flex items-center justify-between text-xs">
                                  <span>Size:</span>
                                  <span className="text-slate-300">{selectedDecorationTypeData.size_x}x{selectedDecorationTypeData.size_y}</span>
                                </div>
                              </div>
                            ),
                          },
                        ];
                      }
                    } else if (placementMode === 'roads') {
                      if (road) {
                        return [
                          {
                            title: 'Road',
                            icon: '🛣️',
                            color: 'gray' as const,
                            content: (
                              <div className="space-y-1 text-xs">
                                <p>Click to remove road</p>
                                <p>Type: {road.road_type}</p>
                              </div>
                            ),
                          },
                        ];
                      } else if (canPlaceRoadHere) {
                        return [
                          {
                            title: 'Place Road',
                            icon: '🛣️',
                            color: 'gray' as const,
                            content: (
                              <div className="space-y-1 text-xs">
                                <p>Click to place road</p>
                                <p>• Roads connect buildings</p>
                                <p>• Road type auto-updates based on connections</p>
                              </div>
                            ),
                          },
                        ];
                      } else {
                        return [
                          {
                            title: 'Cannot Place Road',
                            icon: '⚠️',
                            color: 'red' as const,
                            content: (
                              <div className="space-y-1 text-xs">
                                <p>Cell is occupied by a building or decoration</p>
                                <p>Remove the building/decoration first</p>
                              </div>
                            ),
                          },
                        ];
                      }
                    } else if (placementMode === 'remove' && building && isTopLeft) {
                      const buildingType = buildingTypes.find(bt => bt.building_type === building.building_type);
                      if (buildingType) {
                        return getBuildingTooltip(buildingType, building.level);
                      }
                    } else if (isInteractive && area) {
                      return [
                        {
                          title: area.name,
                          icon: area.icon,
                          color: 'green' as const,
                          content: (
                            <div className="space-y-1 text-xs">
                              <p>Click to visit this area</p>
                            </div>
                          ),
                        },
                      ];
                    } else if (building && isTopLeft) {
                      const buildingType = buildingTypes.find(bt => bt.building_type === building.building_type);
                      if (buildingType) {
                        return getBuildingTooltip(buildingType, building.level);
                      }
                    }
                    return [];
                  };

                  return (
                    <Tooltip key={`cell-${rowIndex}-${colIndex}`} content={getCellTooltipContent()} position="top">
                      <div
                        className={cellClass}
                        onClick={() => handleCellClick(rowIndex, colIndex)}
                        onMouseEnter={() => setHoveredCell({ x: colIndex, y: rowIndex })}
                        onMouseLeave={() => setHoveredCell(null)}
                        role="button"
                        tabIndex={0}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') {
                            handleCellClick(rowIndex, colIndex);
                          }
                        }}
                      >
                        {/* Road layer (bottom) */}
                        {road && (
                          <RoadTile road={road} className="absolute inset-0 z-0" />
                        )}
                        
                        {/* Building preview (semi-transparent) */}
                        {previewBuildingType && (
                          <div className="absolute inset-0 z-10">
                            <BuildingVisual 
                              buildingType={previewBuildingType} 
                              isPreview={true}
                              className="w-full h-full"
                            />
                          </div>
                        )}
                        
                        {/* Building (top layer) */}
                        {building && isTopLeft && (
                          <div className="absolute inset-0 z-20">
                            <BuildingVisual 
                              buildingType={buildingTypes.find(bt => bt.building_type === building.building_type)!}
                              level={building.level}
                              className="w-full h-full"
                            />
                          </div>
                        )}
                        
                        {/* Decoration */}
                        {decoration && isDecorationTopLeft && (
                          <span className="text-2xl select-none z-20 relative" role="img">
                            {decorationTypes.find(dt => dt.decoration_type === decoration.decoration_type)?.icon || '🎨'}
                          </span>
                        )}
                        
                        {/* Legacy area icons */}
                        {!building && !decoration && !road && area && (
                          <span className="text-lg select-none z-10 relative" role="img" aria-label={area.name}>
                            {area.icon}
                          </span>
                        )}
                      </div>
                    </Tooltip>
                  );
                })
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Status Message */}
      <p className="text-center mt-4 text-sm text-emerald-200 font-mono">
        {placementMode === 'place' 
          ? selectedBuildingTypeData 
            ? `Click on a green cell to place ${selectedBuildingTypeData.name}` 
            : 'Select a building to place'
          : placementMode === 'decorate'
          ? selectedDecorationTypeData
            ? `Click on a pink cell to place ${selectedDecorationTypeData.name}`
            : 'Select a decoration to place'
          : placementMode === 'roads'
          ? 'Click to place or remove roads'
          : placementMode === 'remove'
          ? 'Click on a building, decoration, or road to remove it'
          : 'Click on buildings to navigate to different areas of your town! Use Ctrl+Wheel to zoom, Shift+Drag to pan'}
      </p>

      {/* Expansion Modal */}
      {showExpansionModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowExpansionModal(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-purple-500/50" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Expand Town</h3>
            <p className="text-slate-300 mb-4">
              Current size: {GRID_SIZE}x{GRID_SIZE}
            </p>
            <p className="text-slate-300 mb-6">
              Expanding will increase your town to {(GRID_SIZE + 5)}x{(GRID_SIZE + 5)}
            </p>
            
            <div className="bg-slate-700/50 rounded-lg p-4 mb-6">
              <div className="flex items-center justify-between">
                <span className="text-white font-semibold">Expansion Cost:</span>
                <span className="text-yellow-400 font-bold text-xl">💎 {(expansionCost ?? 0).toLocaleString()}</span>
              </div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowExpansionModal(false)}
                className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={async () => {
                  try {
                    await expandTown('all');
                    setShowExpansionModal(false);
                  } catch (error) {
                    // Error handled in store
                  }
                }}
                disabled={crystals < expansionCost}
                className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                  crystals < expansionCost
                    ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                    : 'bg-purple-600 hover:bg-purple-500 text-white'
                }`}
              >
                {crystals < expansionCost ? 'Insufficient Crystals' : 'Expand'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Building Detail Modal */}
      {showBuildingModal && selectedBuilding && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowBuildingModal(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-blue-500/50" onClick={(e) => e.stopPropagation()}>
            {(() => {
              const buildingType = buildingTypes.find(bt => bt.building_type === selectedBuilding.building_type);
              if (!buildingType) return null;
              
              return (
                <>
                  <div className="flex items-center gap-4 mb-4">
                    <div className="w-16 h-16 flex-shrink-0">
                      <BuildingVisual buildingType={buildingType} level={selectedBuilding.level} className="w-full h-full" />
                    </div>
                    <div>
                      <h3 className="text-2xl font-bold text-white">{buildingType.name}</h3>
                      <p className="text-slate-400 text-sm">Level {selectedBuilding.level} / {buildingType.max_level}</p>
                    </div>
                  </div>

                  <div className="space-y-3 mb-6">
                    {buildingType.category === 'community' && (
                      <div className="bg-blue-900/30 rounded-lg p-3 border border-blue-700/50">
                        <p className="text-blue-200 text-sm font-semibold mb-1">Community Building</p>
                        {buildingType.provides_population > 0 && (
                          <p className="text-white text-xs">Provides {buildingType.provides_population} population</p>
                        )}
                      </div>
                    )}
                    {buildingType.category === 'factory' && (
                      <div className="bg-amber-900/30 rounded-lg p-3 border border-amber-700/50">
                        <p className="text-amber-200 text-sm font-semibold mb-1">Factory Building</p>
                        <p className="text-white text-xs">Click to manage production</p>
                      </div>
                    )}
                    {buildingType.category === 'decoration' && (
                      <div className="bg-green-900/30 rounded-lg p-3 border border-green-700/50">
                        <p className="text-green-200 text-sm font-semibold mb-1">Decoration</p>
                        <p className="text-white text-xs">Enhances your town's appearance</p>
                      </div>
                    )}
                    <div className="bg-slate-700/50 rounded-lg p-3">
                      <p className="text-slate-300 text-xs">Size: {buildingType.size_x}x{buildingType.size_y}</p>
                      <p className="text-slate-300 text-xs">Placed: {new Date(selectedBuilding.created_at).toLocaleDateString()}</p>
                    </div>
                  </div>

                  <div className="flex gap-3">
                    <button
                      onClick={() => setShowBuildingModal(false)}
                      className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                    >
                      Close
                    </button>
                    {buildingType.category === 'factory' && (
                      <button
                        onClick={() => {
                          setShowBuildingModal(false);
                          router.push(`/game/factory?building=${selectedBuilding.building_type}`);
                        }}
                        className="flex-1 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-semibold transition-colors"
                      >
                        Manage Factory
                      </button>
                    )}
                  </div>
                </>
              );
            })()}
          </div>
        </div>
      )}
    </div>
  );
};

export default TownMap;
