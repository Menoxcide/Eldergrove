'use client'

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useCityStore, type Building, type BuildingType } from '@/stores/useCityStore';
import { useDecorationsStore, type Decoration, type DecorationType } from '@/stores/useDecorationsStore';

interface TownMapProps {
  loading?: boolean;
}

// GRID_SIZE will be dynamic based on townSize from store

const getBuildingIcon = (buildingType: string): string => {
  const iconMap: Record<string, string> = {
    'rune_bakery': '🍞',
    'potion_workshop': '🧪',
    'enchanting_lab': '✨',
    'kitchen': '👨‍🍳',
    'town_hall': '🏛️',
    'school': '🏫',
    'hospital': '🏥',
    'cinema': '🎬',
    'fountain': '⛲',
    'statue': '🗿',
    'tree': '🌳'
  };
  return iconMap[buildingType] || '🏠';
};

const TownMap: React.FC<TownMapProps> = ({ loading = false }) => {
  const { claimDailyReward, crystals, population, townSize, expandTown, getExpansionCost, fetchPlayerProfile, loading: playerLoading } = usePlayerStore();
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
  const [isClaiming, setIsClaiming] = useState(false);
  const [placementMode, setPlacementMode] = useState<'view' | 'place' | 'remove' | 'decorate'>('view');
  const [selectedBuildingType, setSelectedBuildingType] = useState<string | null>(null);
  const [selectedDecorationType, setSelectedDecorationType] = useState<string | null>(null);
  const [hoveredCell, setHoveredCell] = useState<{x: number, y: number} | null>(null);
  const [showExpansionModal, setShowExpansionModal] = useState(false);
  const [expansionCost, setExpansionCost] = useState<number>(0);
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
    const unsubscribeBuildings = subscribeToBuildings();
    const unsubscribeDecorations = subscribeToDecorations();
    return () => {
      unsubscribeBuildings();
      unsubscribeDecorations();
    };
  }, [fetchPlayerProfile, fetchBuildings, fetchBuildingTypes, fetchDecorations, fetchDecorationTypes, subscribeToBuildings, subscribeToDecorations]);

  useEffect(() => {
    if (showExpansionModal) {
      getExpansionCost('all').then(setExpansionCost);
    }
  }, [showExpansionModal, getExpansionCost]);

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

  const getCellArea = (row: number, col: number): { name: string; path: string; icon: string } | null => {
    // Check if there's a building here first
    const building = getBuildingAtCell(col, row);
    if (building) {
      const buildingType = buildingTypes.find(bt => bt.building_type === building.building_type);
      if (buildingType && col === building.grid_x && row === building.grid_y) {
        return { name: buildingType.name, path: '#', icon: getBuildingIcon(building.building_type) };
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
    // Mine area (middle-right)
    if (row >= 3 && row < 7 && col > 6) {
      return { name: 'Mine', path: '/game/mine', icon: '⛏️' };
    }
    // Zoo area (bottom-middle)
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
      return;
    }

    // Normal navigation
    const area = getCellArea(row, col);
    if (area && area.path !== '#') {
      router.push(area.path);
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
    for (let dx = 0; dx < buildingType.size_x; dx++) {
      for (let dy = 0; dy < buildingType.size_y; dy++) {
        if (isCellOccupied(x + dx, y + dy)) return false;
        if (x + dx >= GRID_SIZE || y + dy >= GRID_SIZE) return false;
      }
    }
    const hasCrystals = crystals >= buildingType.base_cost_crystals;
    const hasPopulation = (buildingType.population_required || 0) <= (population ?? 0);
    return hasCrystals && hasPopulation;
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

  if (loading || buildingsLoading) {
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
    <div className="w-full max-w-6xl mx-auto p-6 bg-gradient-to-br from-emerald-900 via-green-900 to-amber-900 rounded-2xl shadow-2xl border border-emerald-500/30">
      {/* Controls */}
      <div className="mb-4 flex flex-wrap gap-2">
        <button
          onClick={handleClaimReward}
          disabled={isClaiming}
          className={`px-4 py-2 rounded-lg font-semibold transition-all ${
            isClaiming 
              ? 'bg-gray-400 cursor-not-allowed' 
              : 'bg-yellow-500 hover:bg-yellow-400 text-gray-900'
          }`}
        >
          {isClaiming ? 'Claiming...' : 'Daily Reward'}
        </button>
        <button
          onClick={() => {
            setPlacementMode(placementMode === 'place' ? 'view' : 'place');
            if (placementMode === 'place') setSelectedBuildingType(null);
          }}
          className={`px-4 py-2 rounded-lg font-semibold transition-all ${
            placementMode === 'place' 
              ? 'bg-green-600 text-white' 
              : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
          }`}
        >
          {placementMode === 'place' ? 'Cancel Placement' : 'Place Building'}
        </button>
        <button
          onClick={() => {
            setPlacementMode(placementMode === 'decorate' ? 'view' : 'decorate');
            if (placementMode === 'decorate') {
              setSelectedBuildingType(null);
              setSelectedDecorationType(null);
            }
          }}
          className={`px-4 py-2 rounded-lg font-semibold transition-all ${
            placementMode === 'decorate' 
              ? 'bg-pink-600 text-white' 
              : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
          }`}
        >
          {placementMode === 'decorate' ? 'Cancel Decorate' : 'Place Decoration'}
        </button>
        <button
          onClick={() => {
            setPlacementMode(placementMode === 'remove' ? 'view' : 'remove');
          }}
          className={`px-4 py-2 rounded-lg font-semibold transition-all ${
            placementMode === 'remove' 
              ? 'bg-red-600 text-white' 
              : 'bg-slate-700 text-slate-200 hover:bg-slate-600'
          }`}
        >
          {placementMode === 'remove' ? 'Cancel Remove' : 'Remove Building'}
        </button>
        <button
          onClick={() => setShowExpansionModal(true)}
          className="px-4 py-2 rounded-lg font-semibold transition-all bg-purple-600 text-white hover:bg-purple-500"
        >
          Expand Town
        </button>
        <div className="ml-auto flex items-center gap-3">
          <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
            <span className="text-xl">👥</span>
            <span className="text-white font-mono">
              {playerLoading ? '...' : Number(population || 0).toLocaleString()}
            </span>
          </div>
          <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
            <span className="text-xl">💎</span>
            <span className="text-white font-mono">
              {playerLoading ? '...' : Number(crystals || 0).toLocaleString()}
            </span>
          </div>
        </div>
      </div>

      <div className="flex gap-4">
        {/* Building Selection Panel */}
        {placementMode === 'place' && (
          <div className="w-64 bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20 max-h-[600px] overflow-y-auto">
            <h3 className="text-xl font-bold text-white mb-4">Select Building</h3>
            <div className="space-y-2">
              {buildingTypes.map((bt) => (
                <button
                  key={bt.building_type}
                  onClick={() => setSelectedBuildingType(bt.building_type)}
                  className={`w-full p-3 rounded-lg text-left transition-all ${
                    selectedBuildingType === bt.building_type
                      ? 'bg-green-600 border-2 border-green-400'
                      : 'bg-slate-800/60 hover:bg-slate-700/60 border-2 border-transparent'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <span className="text-3xl">{getBuildingIcon(bt.building_type)}</span>
                    <div className="flex-1">
                      <div className="text-white font-semibold">{bt.name}</div>
                      <div className="text-yellow-400 text-sm">💎 {bt.base_cost_crystals}</div>
                      <div className="flex items-center gap-2 text-xs">
                        <span className="text-slate-400">{bt.size_x}x{bt.size_y}</span>
                        {bt.provides_population > 0 && (
                          <span className="text-green-400">+{bt.provides_population} 👥</span>
                        )}
                        {bt.population_required > 0 && (
                          <span className={`${(population ?? 0) >= bt.population_required ? 'text-green-400' : 'text-red-400'}`}>
                            Requires {bt.population_required} 👥
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Decoration Selection Panel */}
        {placementMode === 'decorate' && (
          <div className="w-64 bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20 max-h-[600px] overflow-y-auto">
            <h3 className="text-xl font-bold text-white mb-4">Select Decoration</h3>
            <div className="space-y-2">
              {decorationTypes.map((dt) => (
                <button
                  key={dt.decoration_type}
                  onClick={() => setSelectedDecorationType(dt.decoration_type)}
                  className={`w-full p-3 rounded-lg text-left transition-all ${
                    selectedDecorationType === dt.decoration_type
                      ? 'bg-pink-600 border-2 border-pink-400'
                      : 'bg-slate-800/60 hover:bg-slate-700/60 border-2 border-transparent'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <span className="text-3xl">{dt.icon}</span>
                    <div className="flex-1">
                      <div className="text-white font-semibold">{dt.name}</div>
                      <div className="text-yellow-400 text-sm">💎 {dt.cost_crystals}</div>
                      <div className="text-slate-400 text-xs">{dt.size_x}x{dt.size_y}</div>
                    </div>
                  </div>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Town Grid */}
        <div className="flex-1 relative w-full aspect-square bg-gradient-to-br from-lime-400 via-green-400 to-emerald-500 p-2 rounded-xl shadow-inner border-4 border-green-600/50 backdrop-blur-sm">
          <div className="w-full h-full grid grid-cols-10 grid-rows-10 gap-px bg-black/20 rounded-lg overflow-hidden">
            {Array.from({ length: GRID_SIZE }, (_, rowIndex) =>
              Array.from({ length: GRID_SIZE }, (_, colIndex) => {
                const building = getBuildingAtCell(colIndex, rowIndex);
                const isTopLeft = building && building.grid_x === colIndex && building.grid_y === rowIndex;
                const decoration = getDecorationAtCell(colIndex, rowIndex);
                const isDecorationTopLeft = decoration && decoration.grid_x === colIndex && decoration.grid_y === rowIndex;
                const area = getCellArea(rowIndex, colIndex);
                const isInteractive = area !== null && placementMode === 'view';
                const isHovered = hoveredCell?.x === colIndex && hoveredCell?.y === rowIndex;
                const canPlace = selectedBuildingTypeData && canPlaceBuilding(selectedBuildingTypeData, colIndex, rowIndex);
                const canPlaceDeco = selectedDecorationTypeData && canPlaceDecoration(selectedDecorationTypeData, colIndex, rowIndex);

                let cellClass = 'aspect-square relative flex items-center justify-center transition-all duration-200 border ';
                if (placementMode === 'place' && selectedBuildingTypeData) {
                  if (canPlace && isHovered) {
                    cellClass += 'bg-green-500/50 border-green-400 cursor-pointer';
                  } else if (!canPlace && isHovered) {
                    cellClass += 'bg-red-500/50 border-red-400 cursor-not-allowed';
                  } else {
                    cellClass += 'bg-gray-400/30 border-gray-500/30';
                  }
                } else if (placementMode === 'decorate' && selectedDecorationTypeData) {
                  if (canPlaceDeco && isHovered) {
                    cellClass += 'bg-pink-500/50 border-pink-400 cursor-pointer';
                  } else if (!canPlaceDeco && isHovered) {
                    cellClass += 'bg-red-500/50 border-red-400 cursor-not-allowed';
                  } else {
                    cellClass += 'bg-gray-400/30 border-gray-500/30';
                  }
                } else if (placementMode === 'remove' && (building && isTopLeft || decoration && isDecorationTopLeft)) {
                  cellClass += isHovered ? 'bg-red-500/50 border-red-400 cursor-pointer' : 'bg-red-500/30 border-red-400/50 cursor-pointer';
                } else if (isInteractive) {
                  cellClass += 'bg-gradient-to-b from-lime-300 via-green-300 to-emerald-400 hover:from-lime-200 hover:to-emerald-300 hover:shadow-lg hover:shadow-emerald-500/50 hover:scale-[1.02] border-green-500/30 cursor-pointer';
                } else {
                  cellClass += 'bg-gradient-to-b from-gray-400 via-gray-500 to-gray-600 hover:from-gray-300 hover:to-gray-500 border-gray-500/30 opacity-60';
                }

                return (
                  <div
                    key={`cell-${rowIndex}-${colIndex}`}
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
                    title={
                      placementMode === 'place' && selectedBuildingTypeData
                        ? canPlace ? `Place ${selectedBuildingTypeData.name}` : 'Cannot place here'
                        : placementMode === 'decorate' && selectedDecorationTypeData
                        ? canPlaceDeco ? `Place ${selectedDecorationTypeData.name}` : 'Cannot place here'
                        : placementMode === 'remove' && building && isTopLeft
                        ? `Remove ${buildingTypes.find(bt => bt.building_type === building.building_type)?.name}`
                        : placementMode === 'remove' && decoration && isDecorationTopLeft
                        ? `Remove ${decorationTypes.find(dt => dt.decoration_type === decoration.decoration_type)?.name}`
                        : isInteractive && area
                        ? `Click to visit ${area.name}`
                        : 'Empty area'
                    }
                  >
                    {building && isTopLeft && (
                      <span className="text-2xl select-none" role="img">
                        {getBuildingIcon(building.building_type)}
                      </span>
                    )}
                    {decoration && isDecorationTopLeft && (
                      <span className="text-2xl select-none" role="img">
                        {decorationTypes.find(dt => dt.decoration_type === decoration.decoration_type)?.icon || '🎨'}
                      </span>
                    )}
                    {!building && !decoration && area && (
                      <span className="text-lg select-none" role="img" aria-label={area.name}>
                        {area.icon}
                      </span>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      <p className="text-center mt-4 text-sm text-emerald-200 font-mono">
        {placementMode === 'place' 
          ? selectedBuildingTypeData 
            ? `Click on a green cell to place ${selectedBuildingTypeData.name}` 
            : 'Select a building to place'
          : placementMode === 'decorate'
          ? selectedDecorationTypeData
            ? `Click on a pink cell to place ${selectedDecorationTypeData.name}`
            : 'Select a decoration to place'
          : placementMode === 'remove'
          ? 'Click on a building or decoration to remove it'
          : 'Click on buildings to navigate to different areas of your town!'}
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
    </div>
  );
};

export default TownMap;