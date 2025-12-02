'use client';

import React, { useState, useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useFarmStore, type FarmState, type Crop } from '@/stores/useFarmStore';
import { useOfflineQueue } from '@/hooks/useOfflineQueue';
import { useSpeedUpsStore } from '@/stores/useSpeedUpsStore';
import { usePremiumShopStore } from '@/stores/usePremiumShopStore';
import { getItemIcon } from '@/lib/itemUtils';
import toast from 'react-hot-toast';

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

const CropField: React.FC<CropFieldProps> = ({ plot }) => {
  const { crop_id, ready_at } = plot;
  const fetchPlots = useFarmStore((state: FarmState) => state.fetchPlots);
  const harvestCrop = useFarmStore((state: FarmState) => state.harvestCrop);
  const crops = useFarmStore((state: FarmState) => state.crops);
  const fetchCrops = useFarmStore((state: FarmState) => state.fetchCrops);
  const { queueAction } = useOfflineQueue();
  const { applyCropSpeedUp } = useSpeedUpsStore();
  const { items: premiumItems, purchaseItem } = usePremiumShopStore();
  const [timeLeft, setTimeLeft] = useState(0);
  const [hasAutoHarvested, setHasAutoHarvested] = useState(false);
  const [showCropSelection, setShowCropSelection] = useState(false);
  const [showSpeedUpModal, setShowSpeedUpModal] = useState(false);
  const [currentCrop, setCurrentCrop] = useState<Crop | null>(null);

  useEffect(() => {
    if (crops.length === 0) {
      fetchCrops();
    }
  }, [crops.length, fetchCrops]);

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
    // Only auto-harvest when crop is actually ready (current time >= ready_at) and we haven't harvested it yet
    const isReady = !!crop_id && !!ready_at && new Date() >= new Date(ready_at) && !hasAutoHarvested;

    if (isReady) {
      setHasAutoHarvested(true);
      const autoHarvest = async () => {
        try {
          console.log(`Auto-harvesting plot ${plot.plot_index}`);
          await queueAction('harvest_plot', { p_plot_index: plot.plot_index });
          // Note: fetchPlots() removed - harvestCrop now handles local state update
        } catch (error) {
          console.error('Auto-harvest failed:', error);
          // Reset flag if harvest fails so it can retry
          setHasAutoHarvested(false);
        }
      };

      autoHarvest();
    }
  }, [crop_id, ready_at, hasAutoHarvested, queueAction, plot.plot_index]);

  // Reset auto-harvest flag when a new crop is planted
  useEffect(() => {
    if (crop_id && !hasAutoHarvested) {
      // Reset flag when a new crop is planted
      setHasAutoHarvested(false);
    }
  }, [crop_id, hasAutoHarvested]);

  const formatTime = (seconds: number): string => {
    if (seconds === 0) return 'Ready!';
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  };

  const handlePlantCrop = async (cropId: number) => {
    try {
      await queueAction('plant_crop', { p_plot_index: plot.plot_index, p_crop_id: cropId });
      await fetchPlots();
      setShowCropSelection(false);
    } catch (error) {
      console.error('Failed to plant crop:', error);
    }
  };

  const handleSpeedUp = async (minutes: number) => {
    try {
      await applyCropSpeedUp(plot.plot_index, minutes);
      setShowSpeedUpModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleBuyAndUseSpeedUp = async (itemId: string, minutes: number) => {
    try {
      await purchaseItem(itemId, true); // Use aether
      await applyCropSpeedUp(plot.plot_index, minutes);
      setShowSpeedUpModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleHarvest = async () => {
    if (!isReady) return;
    try {
      setHasAutoHarvested(true); // Prevent auto-harvest from triggering
      await harvestCrop(plot.plot_index);
      await fetchPlots();
    } catch (error) {
      console.error('Failed to harvest crop:', error);
      setHasAutoHarvested(false); // Reset on error so it can retry
    }
  };

  const isEmpty = !crop_id;
  const isGrowing = !!crop_id && !!ready_at && new Date() < new Date(ready_at);
  const isReady = !!crop_id && !!ready_at && new Date() >= new Date(ready_at);
  const speedUpItems = premiumItems.filter(item => item.item_type === 'speed_up');

  return (
    <>
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
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowSpeedUpModal(true);
                }}
                className="absolute top-1 right-1 bg-purple-600 hover:bg-purple-700 text-white text-xs px-2 py-1 rounded-full transition-colors shadow-lg"
                title="Speed Up Growth"
              >
                ⏩
              </button>
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

    {showCropSelection && (
      <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCropSelection(false)}>
        <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-green-500/50" onClick={(e) => e.stopPropagation()}>
          <h3 className="text-2xl font-bold text-white mb-4">Select Crop to Plant</h3>
          <div className="grid grid-cols-2 gap-3 max-h-96 overflow-y-auto">
            {crops.map((crop) => (
              <button
                key={crop.id}
                onClick={() => handlePlantCrop(crop.id)}
                className="bg-slate-800/60 hover:bg-slate-700/60 rounded-xl p-4 border border-slate-700/50 transition-all flex flex-col items-center gap-2"
              >
                <span className="text-4xl">{getItemIcon(crop.item_id)}</span>
                <span className="text-white font-semibold text-sm">{crop.name}</span>
                <span className="text-yellow-400 text-xs">{crop.grow_minutes} min</span>
              </button>
            ))}
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
};

export default CropField;