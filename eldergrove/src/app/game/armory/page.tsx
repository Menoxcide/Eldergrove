'use client';

import { useEffect, useState, useRef } from 'react';
import ArmoryQueueSlot from '@/components/game/ArmoryQueueSlot';
import ArmoryRecipeCard from '@/components/game/ArmoryRecipeCard';
import { useArmoryStore } from '@/stores/useArmoryStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import Tooltip from '@/components/ui/Tooltip';
import { getActionTooltip } from '@/lib/tooltipUtils';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { getArmoryTypeName } from '@/lib/itemUtils';

export default function ArmoryPage() {
  const {
    armories,
    queue,
    recipes,
    inventory,
    loading,
    fetchArmories,
    fetchQueue,
    fetchRecipes,
    fetchInventory,
    startCraft,
    collectArmory,
    upgradeArmory,
    canCraftRecipe,
    subscribeToQueueUpdates
  } = useArmoryStore();
  const { crystals } = usePlayerStore();
  const [selectedArmory, setSelectedArmory] = useState<string | null>(null);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);
  const hasAutoCollected = useRef(false);

  useEffect(() => {
    fetchArmories();
    fetchQueue();
    fetchRecipes();
    fetchInventory();
    const unsubscribe = subscribeToQueueUpdates();
    return unsubscribe;
  }, [fetchArmories, fetchQueue, fetchRecipes, fetchInventory, subscribeToQueueUpdates]);

  useEffect(() => {
    if (armories.length > 0 && !selectedArmory) {
      setSelectedArmory(armories[0].armory_type);
    }
  }, [armories, selectedArmory]);

  // Auto-collect ready items when they become available
  useEffect(() => {
    if (loading) return;

    if (queue.length === 0) {
      hasAutoCollected.current = false;
      return;
    }

    // Skip if we've already attempted auto-collect for the current queue state
    if (hasAutoCollected.current) return;

    const autoCollectReady = async () => {
      const readySlots = queue.filter(
        (item) => item.finishes_at && new Date(item.finishes_at) <= new Date()
      );

      if (readySlots.length > 0) {
        // Set flag before collecting to prevent duplicate attempts
        hasAutoCollected.current = true;

        // Collect all ready items
        for (const readyItem of readySlots) {
          try {
            await collectArmory(readyItem.slot);
            await new Promise(resolve => setTimeout(resolve, 300));
          } catch (error) {
            console.error('Auto-collect failed for slot', readyItem.slot, error);
          }
        }
      }
    };

    // Auto-collect ready items
    autoCollectReady();
  }, [queue, loading, collectArmory]); // Only run when queue or loading changes

  const handleStartCraft = async (recipeName: string) => {
    if (!selectedArmory) return;
    await startCraft(selectedArmory, recipeName);
    await fetchInventory();
  };

  const maxSlots = 2;
  const currentQueueSlots = queue.filter(q => q.armory_type === selectedArmory).length;
  const emptySlots = maxSlots - currentQueueSlots;

  const selectedArmoryData = selectedArmory 
    ? armories.find(a => a.armory_type === selectedArmory)
    : null;
  const armoryLevel = selectedArmoryData?.level ?? 0;
  const isMaxLevel = armoryLevel >= 5;
  const upgradeCost = armoryLevel > 0 ? 1000 * armoryLevel : 0;

  const handleUpgradeClick = () => {
    if (!selectedArmory || isMaxLevel) return;
    setShowUpgradeModal(true);
  };

  const handleUpgradeConfirm = async () => {
    if (!selectedArmory) return;
    await upgradeArmory(selectedArmory);
    await fetchArmories();
    await fetchInventory();
    setShowUpgradeModal(false);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Armory</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  const currentArmoryQueue = queue.filter(q => q.armory_type === selectedArmory);

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Armory</h1>

        {armories.length > 0 && (
          <div className="mb-6">
            <div className="flex gap-2 flex-wrap mb-2">
              {armories.map((armory) => (
                <Tooltip
                  key={armory.armory_type}
                  content={[
                    {
                      title: getArmoryTypeName(armory.armory_type),
                      icon: '⚔️',
                      color: 'blue' as const,
                      content: (
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <span>Level:</span>
                            <span className="font-bold text-cyan-300">Level {armory.level}</span>
                          </div>
                          <div className="border-t border-slate-700 pt-2 mt-2">
                            <p className="text-xs">• Higher level = more recipes</p>
                            <p className="text-xs">• Upgrade to unlock better equipment</p>
                            <p className="text-xs">• Max level: 5</p>
                          </div>
                        </div>
                      ),
                    },
                  ]}
                  position="bottom"
                >
                  <button
                    onClick={() => setSelectedArmory(armory.armory_type)}
                    className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                      selectedArmory === armory.armory_type
                        ? 'bg-blue-600 text-white'
                        : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                    }`}
                  >
                    {getArmoryTypeName(armory.armory_type)} (Lv.{armory.level})
                  </button>
                </Tooltip>
              ))}
            </div>
            {selectedArmory && (
              <div className="flex gap-2">
                <Tooltip
                  content={getActionTooltip(
                    isMaxLevel
                      ? 'Max Level Reached'
                      : `Upgrade ${getArmoryTypeName(selectedArmory)}`,
                    undefined,
                    isMaxLevel
                      ? ['Armory is at maximum level', 'No further upgrades available']
                      : ['Increases armory level', 'Unlocks new equipment recipes', 'Costs crystals']
                  )}
                  position="bottom"
                >
                  <button
                    onClick={handleUpgradeClick}
                    disabled={isMaxLevel}
                    className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                      isMaxLevel
                        ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                        : 'bg-green-600 hover:bg-green-500 text-white'
                    }`}
                  >
                    {isMaxLevel
                      ? 'Max Level'
                      : `Upgrade ${getArmoryTypeName(selectedArmory)}`}
                  </button>
                </Tooltip>
              </div>
            )}
          </div>
        )}

        {selectedArmory && (
          <>
            <div className="mb-6">
              <h2 className="text-xl font-bold text-white mb-4">Crafting Queue</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {currentArmoryQueue.map((queueItem) => (
                  <ArmoryQueueSlot key={`${queueItem.armory_type}-${queueItem.slot}`} queueItem={queueItem} />
                ))}
                {Array.from({ length: emptySlots }).map((_, index) => (
                  <div
                    key={`empty-${index}`}
                    className="bg-white/5 backdrop-blur-md rounded-lg p-4 border-2 border-dashed border-white/20 flex items-center justify-center min-h-[80px]"
                  >
                    <span className="text-slate-400">Empty Slot {currentArmoryQueue.length + index + 1}</span>
                  </div>
                ))}
                {currentArmoryQueue.length === 0 && emptySlots === 0 && (
                  <div className="col-span-full bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
                    <p className="text-slate-300 text-lg">No crafting queues active</p>
                    <p className="text-slate-400 mt-2">Start crafting equipment to see them here!</p>
                  </div>
                )}
              </div>
            </div>

            <div>
              <h2 className="text-xl font-bold text-white mb-4">Available Recipes</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {recipes.map((recipe) => (
                  <ArmoryRecipeCard
                    key={recipe.id}
                    recipe={recipe}
                    canCraft={canCraftRecipe(recipe)}
                    onStart={() => handleStartCraft(recipe.name)}
                    inventory={inventory}
                  />
                ))}
              </div>
            </div>
          </>
        )}

        {/* Upgrade Armory Modal */}
        {showUpgradeModal && selectedArmory && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowUpgradeModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Upgrade {getArmoryTypeName(selectedArmory)}</h3>
              <div className="mb-4">
                <p className="text-slate-300 mb-2">Current Level: {armoryLevel}</p>
                <p className="text-slate-300 mb-2">New Level: {armoryLevel + 1}</p>
                <p className="text-yellow-400 font-semibold mb-2">Cost: 💎 {upgradeCost.toLocaleString()}</p>
                <p className="text-slate-400 text-sm">Unlocks new equipment recipes</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => setShowUpgradeModal(false)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleUpgradeConfirm}
                  disabled={crystals < upgradeCost}
                  className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                    crystals < upgradeCost
                      ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                      : 'bg-green-600 hover:bg-green-500 text-white'
                  }`}
                >
                  Upgrade
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

