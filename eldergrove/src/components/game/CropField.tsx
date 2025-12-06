'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useFarmStore, type FarmState, type Crop } from '@/stores/useFarmStore';
import { useInventoryStore } from '@/stores/useInventoryStore';
import { useOfflineQueue } from '@/hooks/useOfflineQueue';
import { useSpeedUpsStore } from '@/stores/useSpeedUpsStore';
import { usePremiumShopStore } from '@/stores/usePremiumShopStore';
import { useAdSpeedUp } from '@/hooks/useAdSpeedUp';
import { getItemIcon, getSeedItemId } from '@/lib/itemUtils';
import { useErrorHandler } from '@/hooks/useErrorHandler';
import Tooltip from '@/components/ui/Tooltip';
import { getCropTooltip, getActionTooltip } from '@/lib/tooltipUtils';

interface FarmPlot {
  player_id: string;
  plot_index: number;
  crop_id: number | null;
  planted_at: string | null;
  ready_at: string | null;
}

interface CropFieldProps {
  plot: FarmPlot;
}

const CropField: React.FC<CropFieldProps> = React.memo(({ plot }) => {
  const { crop_id, ready_at } = plot;
  const fetchPlots = useFarmStore((state: FarmState) => state.fetchPlots);
  const harvestCrop = useFarmStore((state: FarmState) => state.harvestCrop);
  const crops = useFarmStore((state: FarmState) => state.crops);
  const fetchCrops = useFarmStore((state: FarmState) => state.fetchCrops);
  const inventory = useInventoryStore((state) => state.inventory);
  const fetchInventory = useInventoryStore((state) => state.fetchInventory);
  const { queueAction } = useOfflineQueue();
  const { applyCropSpeedUp } = useSpeedUpsStore();
  const { items: premiumItems, purchaseItem } = usePremiumShopStore();
  const { watchAdForSpeedUp, canWatchAd, adsRemaining, loading: adLoading } = useAdSpeedUp();
  const [timeLeft, setTimeLeft] = useState(0);
  const [hasAutoHarvested, setHasAutoHarvested] = useState(false);
  const [harvestRetryCount, setHarvestRetryCount] = useState(0);
  const [isHarvesting, setIsHarvesting] = useState(false); // Prevent duplicate harvest attempts
  const [showCropSelection, setShowCropSelection] = useState(false);
  const [showSpeedUpModal, setShowSpeedUpModal] = useState(false);
  const [currentCrop, setCurrentCrop] = useState<Crop | null>(null);
  const { showError } = useErrorHandler();

  useEffect(() => {
    if (crops.length === 0) {
      fetchCrops();
    }
  }, [crops.length, fetchCrops]);

  useEffect(() => {
    if (showCropSelection) {
      fetchInventory();
    }
  }, [showCropSelection, fetchInventory]);

  useEffect(() => {
    if (crop_id && crops.length > 0) {
      const crop = crops.find(c => c.id === crop_id);
      setCurrentCrop(crop || null);
    } else {
      setCurrentCrop(null);
    }
  }, [crop_id, crops]);

  useEffect(() => {
    if (!ready_at) {
      setTimeLeft(0);
      return;
    }

    const updateTime = () => {
      const now = Date.now();
      const readyTime = new Date(ready_at).getTime();
      setTimeLeft(Math.max(0, (readyTime - now) / 1000));
    };

    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, [ready_at]);

  useEffect(() => {
    const isReady = !!crop_id && !!ready_at && new Date() >= new Date(ready_at) && !hasAutoHarvested && !isHarvesting && harvestRetryCount < 3;

    if (isReady) {
      setHasAutoHarvested(true);
      setIsHarvesting(true);
      const autoHarvest = async () => {
        try {
          await harvestCrop(plot.plot_index);
          setHarvestRetryCount(0); // Reset on success
        } catch (error) {
          const errorMessage = error instanceof Error ? error.message : String(error);
          // Don't log or retry for race conditions (already harvested)
          if (!errorMessage.toLowerCase().includes('no crop to harvest') && 
              !errorMessage.toLowerCase().includes('already harvested')) {
            console.error('Auto-harvest failed:', error);
            setHarvestRetryCount(prev => prev + 1);
            // Only reset hasAutoHarvested if we haven't exceeded max retries
            if (harvestRetryCount < 2) {
              setHasAutoHarvested(false);
            }
          } else {
            // Race condition - plot was already harvested, just reset state
            setHarvestRetryCount(0);
          }
        } finally {
          setIsHarvesting(false);
        }
      };

      const timeoutId = setTimeout(autoHarvest, 100 + (harvestRetryCount * 200)); // Stagger retries
      return () => clearTimeout(timeoutId);
    }
  }, [crop_id, ready_at, hasAutoHarvested, isHarvesting, harvestCrop, plot.plot_index, harvestRetryCount]);

  useEffect(() => {
    if (crop_id && !hasAutoHarvested) {
      setHasAutoHarvested(false);
      setHarvestRetryCount(0); // Reset retry count when new crop is planted
      setIsHarvesting(false); // Reset harvesting flag when new crop is planted
    }
  }, [crop_id, hasAutoHarvested]);

  const formatTime = (seconds: number): string => {
    if (seconds === 0) return 'Ready!';
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  };

  const handlePlantCrop = useCallback(async (cropId: number) => {
    try {
      const crop = crops.find(c => c.id === cropId);
      if (!crop) {
        showError('Crop Not Found', 'The selected crop could not be found.');
        return;
      }

      const seedItemId = getSeedItemId(crop.item_id);
      const seedItem = inventory.find(item => item.item_id === seedItemId);
      const seedCount = seedItem?.quantity || 0;

      if (seedCount < 1) {
        showError('No Seeds Available', `You don't have any seeds to plant ${crop.name}.`, { seedItemId, itemId: crop.item_id, itemName: crop.name }, `Purchase seeds from the seed shop to plant ${crop.name}.`);
        return;
      }

      await queueAction('plant_crop', { p_plot_index: plot.plot_index, p_crop_id: cropId });
      await fetchPlots();
      await fetchInventory();
      setShowCropSelection(false);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to plant crop:', error);
      }
    }
  }, [crops, inventory, plot.plot_index, showError, queueAction, fetchPlots, fetchInventory]);

  const handleSpeedUp = async (minutes: number) => {
    await applyCropSpeedUp(plot.plot_index, minutes);
    setShowSpeedUpModal(false);
  };

  const handleBuyAndUseSpeedUp = async (itemId: string, minutes: number) => {
    await purchaseItem(itemId, true); // Use aether
    await applyCropSpeedUp(plot.plot_index, minutes);
    setShowSpeedUpModal(false);
  };

  const handleWatchAd = async () => {
    await watchAdForSpeedUp('farm', plot.plot_index);
    await fetchPlots(); // Refresh plots to show updated timer
  };

  const handleHarvest = async () => {
    if (!isReady || isHarvesting) return; // Prevent duplicate harvest attempts
    try {
      setIsHarvesting(true);
      setHasAutoHarvested(true); // Prevent auto-harvest from triggering
      await harvestCrop(plot.plot_index);
      setHarvestRetryCount(0);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      // Don't show error for race conditions (already harvested)
      if (!errorMessage.toLowerCase().includes('no crop to harvest') && 
          !errorMessage.toLowerCase().includes('already harvested')) {
        console.error('Failed to harvest crop:', error);
        setHarvestRetryCount(prev => prev + 1);
        // Only reset hasAutoHarvested if we haven't exceeded max retries
        if (harvestRetryCount < 2) {
          setHasAutoHarvested(false);
        }
      } else {
        // Race condition - plot was already harvested, just reset state
        setHarvestRetryCount(0);
      }
    } finally {
      setIsHarvesting(false);
    }
  };

  const isEmpty = !crop_id;
  const isGrowing = !!crop_id && !!ready_at && new Date() < new Date(ready_at);
  const isReady = !!crop_id && !!ready_at && new Date() >= new Date(ready_at);
  const speedUpItems = premiumItems.filter(item => item.item_type === 'speed_up');

  const getPlotTooltipContent = () => {
    if (isEmpty) {
      return [
        {
          title: 'Empty Plot',
          icon: '🌱',
          color: 'gray' as const,
          content: (
            <div className="space-y-1 text-xs">
              <p>Click to plant a crop</p>
              <p>• Requires seeds in inventory</p>
              <p>• Each crop has different grow times</p>
              <p>• Harvest when ready to earn rewards</p>
            </div>
          ),
        },
      ];
    } else if (isReady && currentCrop) {
      return getCropTooltip(currentCrop);
    } else if (isGrowing && currentCrop) {
      const sections = getCropTooltip(currentCrop);
      sections.push({
        title: 'Growing',
        icon: '⏳',
        color: 'yellow' as const,
        content: (
          <div className="space-y-1 text-xs">
            <p>Time remaining: {formatTime(timeLeft)}</p>
            <p>• Use speed-ups to finish faster</p>
            <p>• Watch ads for free 30-min speed-up</p>
            <p>• Click when ready to harvest</p>
          </div>
        ),
      });
      return sections;
    }
    return [];
  };

  return (
    <>
      <Tooltip content={getPlotTooltipContent()} position="top">
        <div 
          className={`relative w-24 h-24 border-4 border-gray-300 rounded-2xl shadow-xl bg-gradient-to-br from-amber-200 via-yellow-300 to-orange-300 transition-all duration-200 group ${
            isReady ? 'cursor-pointer hover:scale-105' : isGrowing ? 'cursor-default' : 'cursor-pointer hover:scale-105'
          }`}
          onClick={isReady ? handleHarvest : undefined}
        >
        {isEmpty ? (
          <button
            className="absolute inset-0 rounded-2xl flex flex-col items-center justify-center bg-gradient-to-br from-emerald-500 to-green-600 text-white font-bold text-xs hover:from-emerald-400 hover:to-green-500 transition-all px-1 py-1 border border-white/20"
            onClick={() => setShowCropSelection(true)}
          >
            Plant
            <br />
            Crop
          </button>
      ) : (
        <>
          <div className="absolute inset-0 bg-gradient-to-br from-green-400 via-emerald-500 to-teal-500 rounded-2xl opacity-90" />
          <div className="absolute inset-0 flex items-end justify-center pb-2 px-1">
            <div className="w-14 h-14 bg-gradient-to-br from-lime-300 to-green-400 rounded-xl shadow-lg flex items-center justify-center border-2 border-white/50">
              <span className="text-2xl">{currentCrop ? getItemIcon(currentCrop.item_id) : '🌿'}</span>
            </div>
          </div>
          {isGrowing && (
            <>
              <div className="absolute -bottom-3 left-1/2 transform -translate-x-1/2 bg-black/80 backdrop-blur-sm text-white text-xs font-mono px-2 py-1 rounded-full shadow-lg border border-white/30 whitespace-nowrap">
                {formatTime(timeLeft)}
              </div>
              <div className="absolute top-1 right-1 flex flex-col gap-1">
                <Tooltip content={getActionTooltip('Speed Up Growth', undefined, ['Use speed-up items', 'Reduce grow time by item minutes', 'Available in premium shop'])} position="left">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setShowSpeedUpModal(true);
                    }}
                    className="bg-purple-600 hover:bg-purple-700 text-white text-xs px-2 py-1 rounded-full transition-colors shadow-lg"
                  >
                    ⏩
                  </button>
                </Tooltip>
                {canWatchAd && (
                  <Tooltip content={getActionTooltip(`Watch Ad (${adsRemaining} remaining)`, undefined, ['Free 30-minute speed-up', `${adsRemaining} ads remaining today`, 'No cost required'])} position="left">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleWatchAd();
                      }}
                      disabled={adLoading}
                      className="bg-green-600 hover:bg-green-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs px-2 py-1 rounded-full transition-colors shadow-lg"
                    >
                      📺
                    </button>
                  </Tooltip>
                )}
              </div>
            </>
          )}
          {isReady && (
            <div className="absolute -bottom-3 left-1/2 transform -translate-x-1/2 bg-green-600/90 backdrop-blur-sm text-white text-xs font-mono px-2 py-1 rounded-full shadow-lg border border-white/30 whitespace-nowrap">
              Ready!
            </div>
          )}
        </>
      )}
      </div>
    </Tooltip>

    {showCropSelection && (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCropSelection(false)}>
        <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-green-500/50" onClick={(e) => e.stopPropagation()}>
          <h3 className="text-2xl font-bold text-white mb-4">Select Crop to Plant</h3>
          <div className="grid grid-cols-2 gap-3 max-h-96 overflow-y-auto">
            {crops.map((crop) => {
              // Seeds use item_id 100-110, crops use item_id 1-10
              const seedItemId = getSeedItemId(crop.item_id);
              const seedItem = inventory.find(item => item.item_id === seedItemId);
              const seedCount = seedItem?.quantity || 0;
              const hasSeeds = seedCount > 0;
              return (
                <Tooltip key={crop.id} content={getCropTooltip(crop, seedCount)} position="top">
                  <button
                    onClick={() => hasSeeds && handlePlantCrop(crop.id)}
                    disabled={!hasSeeds}
                    className={`rounded-xl p-4 border transition-all flex flex-col items-center gap-2 ${
                      hasSeeds
                        ? 'bg-slate-800/60 hover:bg-slate-700/60 border-slate-700/50 cursor-pointer'
                        : 'bg-slate-900/60 border-slate-800/50 cursor-not-allowed opacity-60'
                    }`}
                  >
                    <span className="text-4xl">{getItemIcon(crop.item_id)}</span>
                    <span className="text-white font-semibold text-sm">{crop.name}</span>
                    <span className="text-yellow-400 text-xs">{crop.grow_minutes} min</span>
                    <span className={`text-xs font-medium ${hasSeeds ? 'text-green-400' : 'text-red-400'}`}>
                      Seeds: {seedCount}
                    </span>
                    {!hasSeeds && (
                      <span className="text-red-400 text-xs font-medium">No seeds available</span>
                    )}
                  </button>
                </Tooltip>
              );
            })}
          </div>
          <button
            onClick={() => setShowCropSelection(false)}
            className="mt-4 w-full py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    )}

    {/* Speed-Up Modal */}
    {showSpeedUpModal && (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowSpeedUpModal(false)}>
        <div className="bg-gradient-to-br from-green-800 to-emerald-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-purple-500/50" onClick={(e) => e.stopPropagation()}>
          <h3 className="text-2xl font-bold text-white mb-4">Speed Up Crop Growth</h3>
          <p className="text-slate-300 mb-4">Time remaining: {formatTime(timeLeft)}</p>
          
          {/* Watch Ad Option */}
          {canWatchAd && (
            <button
              onClick={async () => {
                await handleWatchAd();
                setShowSpeedUpModal(false);
              }}
              disabled={adLoading}
              className="w-full flex items-center justify-between p-3 bg-green-700/60 hover:bg-green-600 disabled:bg-gray-600 disabled:cursor-not-allowed rounded-lg transition-colors mb-4"
            >
              <div className="flex items-center gap-3">
                <span className="text-2xl">📺</span>
                <div className="text-left">
                  <div className="text-white font-semibold">Watch Ad</div>
                  <div className="text-green-300 text-sm">-30 minutes (Free)</div>
                </div>
              </div>
              <div className="text-green-400 font-bold">{adsRemaining} remaining</div>
            </button>
          )}

          <div className="space-y-2 mb-4">
            {speedUpItems.map((item) => {
              const minutes = item.metadata?.minutes || 60;
              return (
                <button
                  key={item.id}
                  onClick={() => handleBuyAndUseSpeedUp(item.item_id, minutes)}
                  className="w-full flex items-center justify-between p-3 bg-slate-700/60 hover:bg-slate-600 rounded-lg transition-colors"
                >
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">{item.icon}</span>
                    <div className="text-left">
                      <div className="text-white font-semibold">{item.name}</div>
                      <div className="text-purple-300 text-sm">-{minutes} minutes</div>
                    </div>
                  </div>
                  <div className="text-purple-400 font-bold">✨ {item.cost_aether}</div>
                </button>
              );
            })}
          </div>

          <button
            onClick={() => setShowSpeedUpModal(false)}
            className="w-full px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>
    )}
    </>
  );
});

CropField.displayName = 'CropField';

export default CropField;