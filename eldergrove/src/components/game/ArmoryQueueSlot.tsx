'use client';

import React, { useState, useEffect } from 'react';
import type { ArmoryQueueItem } from '@/stores/useArmoryStore';
import { useOfflineQueue } from '@/hooks/useOfflineQueue';
import { useArmoryStore } from '@/stores/useArmoryStore';
import { createClient } from '@/lib/supabase/client';
import Tooltip from '@/components/ui/Tooltip';
import { getActionTooltip } from '@/lib/tooltipUtils';

interface ArmoryQueueSlotProps {
  queueItem: ArmoryQueueItem;
}

const ArmoryQueueSlot: React.FC<ArmoryQueueSlotProps> = ({ queueItem }) => {
  const { finishes_at, slot, recipe_id, armory_type } = queueItem;
  const [timeLeft, setTimeLeft] = useState(0);
  const [recipeName, setRecipeName] = useState<string>('Equipment');
  const { queueAction } = useOfflineQueue();
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
      await queueAction('collect_armory', { p_slot: slot });
    } catch (error) {
      // Error is already handled by the queue function
    }
  };

  const isReady = timeLeft <= 0 && finishes_at;

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
              <span className="text-slate-300 capitalize">{armory_type}</span>
            </div>
            {isReady ? (
              <div className="border-t border-slate-700 pt-2 mt-2">
                <p className="text-xs text-green-300 font-semibold">Ready to collect!</p>
                <p className="text-xs text-slate-300 mt-1">Click Collect to receive equipment</p>
              </div>
            ) : (
              <div className="border-t border-slate-700 pt-2 mt-2">
                <p className="text-xs">Time remaining: {formatTime(timeLeft)}</p>
                <p className="text-xs text-slate-300 mt-1">Crafting in progress...</p>
              </div>
            )}
          </div>
        ),
      },
    ];
  };

  return (
    <Tooltip content={getSlotTooltipContent()} position="top">
      <div className="text-sm bg-white/10 p-3 rounded-lg shadow-md border border-white/20 flex flex-col sm:flex-row items-center justify-between hover:bg-white/20 transition-all gap-2">
        <span className="font-semibold text-white/90">Slot {slot}: {recipeName}</span>
        <div className="flex items-center gap-2">
          <span className="font-mono bg-gradient-to-r from-black/90 to-gray-900 backdrop-blur-sm text-white text-xs px-3 py-1 rounded-full shadow-lg border border-white/30 min-w-[60px] text-center">
            {formatTime(timeLeft)}
          </span>
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
  );
};

export default ArmoryQueueSlot;

