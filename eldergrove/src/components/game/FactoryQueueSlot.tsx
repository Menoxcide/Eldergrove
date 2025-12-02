'use client';

import React, { useState, useEffect } from 'react';
import type { FactoryQueueItem } from '@/stores/useFactoryStore';
import { useOfflineQueue } from '@/hooks/useOfflineQueue';
import { useSpeedUpsStore } from '@/stores/useSpeedUpsStore';
import { usePremiumShopStore } from '@/stores/usePremiumShopStore';
import { createClient } from '@/lib/supabase/client';
import toast from 'react-hot-toast';

interface FactoryQueueSlotProps {
  queueItem: FactoryQueueItem;
}

const FactoryQueueSlot: React.FC<FactoryQueueSlotProps> = ({ queueItem }) => {
  const { finishes_at, slot, recipe_id, factory_type } = queueItem;
  const [timeLeft, setTimeLeft] = useState(0);
  const [recipeName, setRecipeName] = useState<string>('Item');
  const [showSpeedUpModal, setShowSpeedUpModal] = useState(false);
  const { queueAction } = useOfflineQueue();
  const { applyFactorySpeedUp } = useSpeedUpsStore();
  const { items: premiumItems, purchaseItem } = usePremiumShopStore();

  useEffect(() => {
    const fetchRecipeName = async () => {
      try {
        const supabase = createClient();
        const { data, error } = await supabase
          .from('recipes')
          .select('name')
          .eq('id', recipe_id)
          .single();
        
        if (!error && data) {
          setRecipeName(data.name);
        }
      } catch (error) {
        console.error('Error fetching recipe name:', error);
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
    try {
      await queueAction('collect_factory', { p_slot: slot });
    } catch (error) {
      // Error is already handled by the queue function
    }
  };

  const handleSpeedUp = async (minutes: number) => {
    try {
      await applyFactorySpeedUp(factory_type, slot, minutes);
      setShowSpeedUpModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleBuyAndUseSpeedUp = async (itemId: string, minutes: number) => {
    try {
      await purchaseItem(itemId, true); // Use aether
      await applyFactorySpeedUp(factory_type, slot, minutes);
      setShowSpeedUpModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  const isReady = timeLeft <= 0 && finishes_at;
  const speedUpItems = premiumItems.filter(item => item.item_type === 'speed_up');

  return (
    <div className="text-sm bg-white/10 p-3 rounded-lg shadow-md border border-white/20 flex flex-col sm:flex-row items-center justify-between hover:bg-white/20 transition-all gap-2">
      <span className="font-semibold text-white/90">Slot {slot}: {recipeName}</span>
      <div className="flex items-center gap-2">
        <span className="font-mono bg-gradient-to-r from-black/90 to-gray-900 backdrop-blur-sm text-white text-xs px-3 py-1 rounded-full shadow-lg border border-white/30 min-w-[60px] text-center">
          {formatTime(timeLeft)}
        </span>
        {!isReady && (
          <button
            onClick={() => setShowSpeedUpModal(true)}
            className="px-3 py-1 bg-purple-600 hover:bg-purple-700 text-white text-xs rounded-full transition-colors whitespace-nowrap"
          >
            ⏩ Speed Up
          </button>
        )}
        {isReady && (
          <button
            onClick={handleCollect}
            className="px-3 py-1 bg-green-600 hover:bg-green-700 text-white text-xs rounded-full transition-colors whitespace-nowrap"
          >
            Collect
          </button>
        )}
      </div>

      {/* Speed-Up Modal */}
      {showSpeedUpModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowSpeedUpModal(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-purple-500/50" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Speed Up Production</h3>
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
    </div>
  );
};

export default FactoryQueueSlot;