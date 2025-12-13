'use client';

import React, { useState, useEffect, useCallback } from 'react';
import type { ArmoryQueueItem } from '@/stores/useArmoryStore';
import { useOfflineQueue } from '@/hooks/useOfflineQueue';
import { useSpeedUpsStore } from '@/stores/useSpeedUpsStore';
import { usePremiumShopStore } from '@/stores/usePremiumShopStore';
import { useAdSpeedUp } from '@/hooks/useAdSpeedUp';
import { useErrorHandler } from '@/hooks/useErrorHandler';
import { useArmoryStore } from '@/stores/useArmoryStore';
import { createClient } from '@/lib/supabase/client';
import Tooltip from '@/components/ui/Tooltip';
import { getActionTooltip } from '@/lib/tooltipUtils';
import { getArmoryTypeName } from '@/lib/itemUtils';

interface ArmoryQueueSlotProps {
  queueItem: ArmoryQueueItem;
}

const ArmoryQueueSlot: React.FC<ArmoryQueueSlotProps> = React.memo(({ queueItem }) => {
  const { finishes_at, slot, recipe_id, armory_type } = queueItem;
  const [timeLeft, setTimeLeft] = useState(0);
  const [recipeName, setRecipeName] = useState<string>('Equipment');
  const [showSpeedUpModal, setShowSpeedUpModal] = useState(false);
  const { queueAction } = useOfflineQueue();
  const { applyArmorySpeedUp } = useSpeedUpsStore();
  const { handleError } = useErrorHandler();
  const { items: premiumItems, purchaseItem } = usePremiumShopStore();
  const { watchAdForSpeedUp, canWatchAd, adsRemaining, loading: adLoading } = useAdSpeedUp();
  const { fetchQueue } = useArmoryStore();

  useEffect(() => {
    const fetchRecipeName = async () => {
      try {
        const supabase = createClient();
        const { data, error } = await supabase
          .from('armory_recipes')
          .select('name')
          .eq('id', recipe_id)
          .single();
        
        if (!error && data) {
          setRecipeName(data.name);
        }
      } catch (error) {
        handleError(error, 'Error fetching recipe name');
      }
    };

    if (recipe_id) {
      fetchRecipeName();
    }
  }, [recipe_id]);

  useEffect(() => {
    if (!finishes_at) {
      setTimeLeft(0);
      return;
    }

    const updateTime = () => {
      const now = Date.now();
      const finishTime = new Date(finishes_at).getTime();
      setTimeLeft(Math.max(0, (finishTime - now) / 1000));
    };

    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, [finishes_at]);

  const formatTime = (seconds: number): string => {
    if (seconds <= 0) return 'Ready!';
    const minutes = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  };

  const handleCollect = async () => {
    await queueAction('collect_armory', { p_slot: slot });
  };

  const handleSpeedUp = async (minutes: number) => {
    await applyArmorySpeedUp(armory_type, slot, minutes);
    setShowSpeedUpModal(false);
  };

  const handleBuyAndUseSpeedUp = async (itemId: string, minutes: number) => {
    await purchaseItem(itemId, true);
    await applyArmorySpeedUp(armory_type, slot, minutes);
    setShowSpeedUpModal(false);
  };

  const handleWatchAd = async () => {
    try {
      await watchAdForSpeedUp('armory', slot);
      await fetchQueue();
    } catch (error) {
      // Error is handled in the hook, but ensure queue refreshes even on error
      await fetchQueue().catch(() => {
        // Silently fail queue refresh if it errors
      });
    }
  };

  const isReady = timeLeft <= 0 && finishes_at;
  const speedUpItems = premiumItems.filter(item => item.item_type === 'speed_up');

  const getSlotTooltipContent = () => {
    return [
      {
        title: `Crafting Slot ${slot}`,
        icon: '⚔️',
        color: 'blue' as const,
        content: (
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span>Recipe:</span>
              <span className="font-bold text-cyan-300">{recipeName}</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Armory:</span>
              <span className="text-slate-300">{getArmoryTypeName(armory_type)}</span>
            </div>
            {isReady ? (
              <div className="border-t border-slate-700 pt-2 mt-2">
                <p className="text-xs text-green-300 font-semibold">Ready to collect!</p>
                <p className="text-xs text-slate-300 mt-1">Click Collect to receive equipment</p>
              </div>
            ) : (
              <div className="border-t border-slate-700 pt-2 mt-2">
                <p className="text-xs">Time remaining: {formatTime(timeLeft)}</p>
                <p className="text-xs text-slate-300 mt-1">Use speed-ups to finish faster</p>
              </div>
            )}
          </div>
        ),
      },
    ];
  };

  return (
    <>
      <Tooltip content={getSlotTooltipContent()} position="top">
        <div className="text-sm bg-white/10 p-3 rounded-lg shadow-md border border-white/20 flex flex-col sm:flex-row items-center justify-between hover:bg-white/20 transition-all gap-2">
          <span className="font-semibold text-white/90">Slot {slot}: {recipeName}</span>
          <div className="flex items-center gap-2">
            <span className="font-mono bg-gradient-to-r from-black/90 to-gray-900 backdrop-blur-sm text-white text-xs px-3 py-1 rounded-full shadow-lg border border-white/30 min-w-[60px] text-center">
              {formatTime(timeLeft)}
            </span>
            {!isReady && (
              <Tooltip content={getActionTooltip('Speed Up Production', undefined, ['Use speed-up items', 'Reduce production time', 'Watch ads for free speed-up'])} position="top">
                <button
                  onClick={() => setShowSpeedUpModal(true)}
                  className="px-3 py-1 bg-purple-600 hover:bg-purple-700 text-white text-xs rounded-full transition-colors whitespace-nowrap"
                >
                  ⏩ Speed Up
                </button>
              </Tooltip>
            )}
            {isReady && (
              <Tooltip content={getActionTooltip('Collect Equipment', undefined, ['Receive crafted equipment', 'Adds to inventory', 'Frees up slot'])} position="top">
                <button
                  onClick={handleCollect}
                  className="px-3 py-1 bg-green-600 hover:bg-green-700 text-white text-xs rounded-full transition-colors whitespace-nowrap"
                >
                  Collect
                </button>
              </Tooltip>
            )}
          </div>
        </div>
      </Tooltip>

      {/* Speed-Up Modal */}
      {showSpeedUpModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowSpeedUpModal(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-purple-500/50" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Speed Up Production</h3>
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

ArmoryQueueSlot.displayName = 'ArmoryQueueSlot';

export default ArmoryQueueSlot;

