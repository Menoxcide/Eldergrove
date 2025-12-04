'use client';

import { useEffect, useState, useRef } from 'react';
import FactoryQueueSlot from '@/components/game/FactoryQueueSlot';
import RecipeCard from '@/components/game/RecipeCard';
import { useFactoryStore } from '@/stores/useFactoryStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useErrorHandler } from '@/hooks/useErrorHandler';
import Tooltip from '@/components/ui/Tooltip';
import { getActionTooltip } from '@/lib/tooltipUtils';
import { createClient } from '@/lib/supabase/client';
import { getItemName, getItemIcon } from '@/lib/itemUtils';

export default function FactoryPage() {
  const {
    factories,
    queue,
    recipes,
    inventory,
    loading,
    slotInfo,
    fetchFactories,
    fetchQueue,
    fetchRecipes,
    fetchInventory,
    getSlotInfo,
    purchaseFactorySlot,
    startProduction,
    collectFactory,
    upgradeFactory,
    canCraftRecipe,
    subscribeToQueueUpdates
  } = useFactoryStore();
  const { crystals } = usePlayerStore();
  const { showError } = useErrorHandler();
  const [selectedFactory, setSelectedFactory] = useState<string | null>(null);
  const [showUpgradeModal, setShowUpgradeModal] = useState(false);
  const [showPurchaseSlotModal, setShowPurchaseSlotModal] = useState(false);
  const [upgradeCost, setUpgradeCost] = useState<{
    crystals: number;
    materials: Array<{ itemId: number; quantity: number }>;
    unlocksQueueSlot: boolean;
    speedMultiplier: number;
  } | null>(null);
  const hasAutoCollected = useRef(false);

  useEffect(() => {
    fetchFactories();
    fetchQueue();
    fetchRecipes();
    fetchInventory();
    getSlotInfo();
    const unsubscribe = subscribeToQueueUpdates();
    return unsubscribe;
  }, [fetchFactories, fetchQueue, fetchRecipes, fetchInventory, getSlotInfo, subscribeToQueueUpdates]);

  // Auto-collect ready items when page loads (only once)
  useEffect(() => {
    if (hasAutoCollected.current || loading) return;
    
    const autoCollectReady = async () => {
      const readySlots = queue.filter(
        (item) => item.finishes_at && new Date(item.finishes_at) <= new Date()
      );
      
      if (readySlots.length > 0) {
        hasAutoCollected.current = true;
        // Collect all ready items
        for (const readyItem of readySlots) {
          try {
            await collectFactory(readyItem.slot);
            // Small delay between collections to avoid overwhelming the UI
            await new Promise(resolve => setTimeout(resolve, 300));
          } catch (error) {
            // Error already handled in store
            console.error('Auto-collect failed for slot', readyItem.slot, error);
          }
        }
      }
    };

    // Only auto-collect if we have queue data and haven't already done it
    if (queue.length > 0) {
      autoCollectReady();
    }
  }, [queue, loading, collectFactory]); // Only run when queue or loading changes

  useEffect(() => {
    if (factories.length > 0 && !selectedFactory) {
      setSelectedFactory(factories[0].factory_type);
    }
  }, [factories, selectedFactory]);

  const maxSlots = slotInfo?.max_slots || 2;
  // Global slot count (shared across all factories)
  const currentQueueSlots = queue.length;
  // Per-factory queue for display purposes
  const currentFactoryQueue = queue.filter(q => q.factory_type === selectedFactory);
  const emptySlots = Math.max(0, maxSlots - currentQueueSlots);

  const handleStartProduction = async (recipeName: string) => {
    if (!selectedFactory) return;
    
    // Pre-validation: Check if global slots are available
    if (currentQueueSlots >= maxSlots) {
      showError(
        'Factory Queue Full',
        `All factory production slots are full (${currentQueueSlots}/${maxSlots} slots used).`,
        { maxSlots, currentSlots: currentQueueSlots },
        'Wait for current production to finish, or purchase additional factory slots to increase capacity.'
      );
      return;
    }
    
    // Pre-validation: Check if recipe can be crafted
    const recipe = recipes.find(r => r.name === recipeName);
    if (recipe && !canCraftRecipe(recipe)) {
      // Find which resource is missing
      const itemNameToId: Record<string, number> = {
        'wheat': 1, 'carrot': 2, 'potato': 3, 'tomato': 4, 'corn': 5,
        'pumpkin': 6, 'bread': 8, 'berry': 11, 'herbs': 12,
        'magic_mushroom': 13, 'enchanted_flower': 14
      };
      
      for (const [itemName, requiredQty] of Object.entries(recipe.input)) {
        const itemId = itemNameToId[itemName.toLowerCase()];
        if (!itemId) continue;
        
        const inventoryItem = inventory.find(inv => inv.item_id === itemId);
        const availableQty = inventoryItem?.quantity || 0;
        
        if (availableQty < requiredQty) {
          const { getItemName } = await import('@/lib/itemUtils');
          showError(
            'Not Enough Resources',
            `You need ${(requiredQty - availableQty).toLocaleString()} more ${getItemName(itemId)} to craft ${recipeName}.`,
            { itemId, required: requiredQty, available: availableQty },
            `Gather more ${getItemName(itemId)} by harvesting crops, completing production, or purchasing from the shop.`
          );
          return;
        }
      }
    }
    
    try {
      await startProduction(selectedFactory, recipeName);
      await fetchInventory(); // Refresh inventory after starting
    } catch (error) {
      // Error already handled in store
    }
  };
  
  // Get selected factory info for upgrade button
  const selectedFactoryData = selectedFactory 
    ? factories.find(f => f.factory_type === selectedFactory)
    : null;
  const factoryLevel = selectedFactoryData?.level ?? 0;
  const isMaxLevel = factoryLevel >= 5;

  // Fetch upgrade cost for factory
  const fetchUpgradeCost = async (factoryType: string, currentLevel: number) => {
    try {
      const supabase = createClient();
      // First, normalize factory_type to building_type
      const { data: buildingTypeData } = await supabase
        .from('building_types')
        .select('building_type')
        .or(`building_type.eq.${factoryType},name.eq.${factoryType}`)
        .single();

      const buildingType = buildingTypeData?.building_type || factoryType.toLowerCase().replace(/\s+/g, '_');
      const newLevel = currentLevel + 1;

      // Fetch upgrade cost
      const { data, error } = await supabase
        .from('building_upgrade_costs')
        .select('*')
        .eq('building_type', buildingType)
        .eq('from_level', currentLevel)
        .eq('to_level', newLevel)
        .single();

      if (error || !data) {
        console.error('Error fetching upgrade cost:', error);
        return null;
      }

      // Parse materials
      const materials: Array<{ itemId: number; quantity: number }> = [];
      if (data.cost_materials) {
        for (const [itemIdStr, quantity] of Object.entries(data.cost_materials)) {
          materials.push({
            itemId: parseInt(itemIdStr),
            quantity: quantity as number
          });
        }
      }

      return {
        crystals: data.cost_crystals,
        materials,
        unlocksQueueSlot: data.unlocks_queue_slot || false,
        speedMultiplier: data.production_speed_multiplier || 1.0
      };
    } catch (error) {
      console.error('Error fetching upgrade cost:', error);
      return null;
    }
  };

  // Handle upgrade button click
  const handleUpgradeClick = async () => {
    if (!selectedFactory || isMaxLevel) return;
    
    const cost = await fetchUpgradeCost(selectedFactory, factoryLevel);
    if (cost) {
      setUpgradeCost(cost);
      setShowUpgradeModal(true);
    }
  };

  // Handle upgrade confirmation
  const handleUpgradeConfirm = async () => {
    if (!selectedFactory) return;
    try {
      await upgradeFactory(selectedFactory);
      await fetchFactories();
      await fetchInventory();
      setShowUpgradeModal(false);
      setUpgradeCost(null);
    } catch (error) {
      // Error handled in store
    }
  };

  // Handle purchase slot click
  const handlePurchaseSlotClick = () => {
    setShowPurchaseSlotModal(true);
  };

  // Handle purchase slot confirmation
  const handlePurchaseSlotConfirm = async () => {
    try {
      await purchaseFactorySlot();
      await getSlotInfo();
      setShowPurchaseSlotModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Factory</h1>
          <div className="flex justify-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-500"></div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Factory</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            {slotInfo && (
              <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
                <span className="text-white text-sm">
                  Slots: {slotInfo.current_slots_used}/{slotInfo.max_slots}
                </span>
              </div>
            )}
            {slotInfo && slotInfo.next_cost > 0 && (
              <Tooltip
                content={getActionTooltip(
                  'Purchase Factory Slot',
                  slotInfo.next_cost,
                  [`Increases max slots from ${slotInfo.max_slots} to ${slotInfo.max_slots + 1}`, 'Allows more simultaneous production', 'One-time purchase']
                )}
                position="bottom"
              >
                <button
                  onClick={handlePurchaseSlotClick}
                  disabled={crystals < slotInfo.next_cost}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white rounded-lg font-semibold transition-colors"
                >
                  Buy Slot ({slotInfo.next_cost} 💎)
                </button>
              </Tooltip>
            )}
          </div>
        </div>

        {factories.length > 0 && (
          <div className="mb-6">
            <div className="flex gap-2 flex-wrap mb-2">
              {factories.map((factory) => (
                <Tooltip
                  key={factory.factory_type}
                  content={[
                    {
                      title: factory.factory_type,
                      icon: '🏭',
                      color: 'blue' as const,
                      content: (
                        <div className="space-y-2">
                          <div className="flex items-center justify-between">
                            <span>Level:</span>
                            <span className="font-bold text-cyan-300">Level {factory.level}</span>
                          </div>
                          <div className="border-t border-slate-700 pt-2 mt-2">
                            <p className="text-xs">• Higher level = more recipes</p>
                            <p className="text-xs">• Upgrade to unlock better items</p>
                            <p className="text-xs">• Max level: 5</p>
                          </div>
                        </div>
                      ),
                    },
                  ]}
                  position="bottom"
                >
                  <button
                    onClick={() => setSelectedFactory(factory.factory_type)}
                    className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                      selectedFactory === factory.factory_type
                        ? 'bg-blue-600 text-white'
                        : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                    }`}
                  >
                    {factory.factory_type} (Lv.{factory.level})
                  </button>
                </Tooltip>
              ))}
            </div>
            {selectedFactory && (
              <div className="flex gap-2">
                <Tooltip
                  content={getActionTooltip(
                    isMaxLevel ? 'Max Level Reached' : `Upgrade to Level ${factoryLevel + 1}`,
                    undefined,
                    isMaxLevel
                      ? ['Factory is at maximum level', 'No further upgrades available']
                      : ['Increases factory level', 'Unlocks new recipes', 'Costs crystals and materials']
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
                      : `Upgrade to Level ${factoryLevel + 1}`}
                  </button>
                </Tooltip>
              </div>
            )}
          </div>
        )}

        {selectedFactory && (
          <>
            <div className="mb-6">
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-bold text-white">Production Queue</h2>
                {slotInfo && (
                  <div className="text-slate-300 text-sm">
                    {slotInfo.current_slots_used}/{slotInfo.max_slots} slots used
                  </div>
                )}
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {currentFactoryQueue.map((queueItem) => (
                  <FactoryQueueSlot key={`${queueItem.factory_type}-${queueItem.slot}`} queueItem={queueItem} />
                ))}
                {Array.from({ length: emptySlots }).map((_, index) => (
                  <div
                    key={`empty-${index}`}
                    className="bg-white/5 backdrop-blur-md rounded-lg p-4 border-2 border-dashed border-white/20 flex items-center justify-center min-h-[80px]"
                  >
                    <span className="text-slate-400">Empty Slot {currentFactoryQueue.length + index + 1}</span>
                  </div>
                ))}
                {currentFactoryQueue.length === 0 && emptySlots === 0 && (
                  <div className="col-span-full bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
                    <p className="text-slate-300 text-lg">No production queues active</p>
                    <p className="text-slate-400 mt-2">Start crafting items to see them here!</p>
                    {slotInfo && slotInfo.next_cost > 0 && (
                      <p className="text-yellow-400 mt-2 text-sm">
                        Purchase more slots ({slotInfo.next_cost} crystals) to increase capacity
                      </p>
                    )}
                  </div>
                )}
              </div>
            </div>

            <div>
              <h2 className="text-xl font-bold text-white mb-4">Available Recipes</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {recipes.map((recipe) => (
                  <RecipeCard
                    key={recipe.id}
                    recipe={recipe}
                    canCraft={canCraftRecipe(recipe)}
                    onStart={() => handleStartProduction(recipe.name)}
                    inventory={inventory}
                  />
                ))}
              </div>
            </div>
          </>
        )}

        {/* Upgrade Factory Modal */}
        {showUpgradeModal && selectedFactory && upgradeCost && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowUpgradeModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Upgrade {selectedFactory}</h3>
              <div className="mb-4">
                <p className="text-slate-300 mb-2">Current Level: {factoryLevel}</p>
                <p className="text-slate-300 mb-2">New Level: {factoryLevel + 1}</p>
                <p className="text-yellow-400 font-semibold mb-2">Cost: 💎 {upgradeCost.crystals.toLocaleString()}</p>
                {upgradeCost.materials.length > 0 && (
                  <div className="mb-2">
                    <p className="text-slate-300 mb-1">Materials Required:</p>
                    {upgradeCost.materials.map((mat) => {
                      const inventoryItem = inventory.find(inv => inv.item_id === mat.itemId);
                      const hasEnough = (inventoryItem?.quantity || 0) >= mat.quantity;
                      return (
                        <div key={mat.itemId} className={`flex items-center gap-2 ${hasEnough ? 'text-slate-300' : 'text-red-400'}`}>
                          <span>{getItemIcon(mat.itemId)}</span>
                          <span>{getItemName(mat.itemId)}: {mat.quantity.toLocaleString()}</span>
                          <span className="text-sm">({(inventoryItem?.quantity || 0).toLocaleString()} available)</span>
                        </div>
                      );
                    })}
                  </div>
                )}
                {upgradeCost.unlocksQueueSlot && (
                  <p className="text-green-400 text-sm mb-2">✨ Unlocks new queue slot!</p>
                )}
                <p className="text-cyan-400 text-sm">
                  Production speed: {((1 - upgradeCost.speedMultiplier) * 100).toFixed(0)}% faster
                </p>
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
                  disabled={
                    crystals < upgradeCost.crystals ||
                    upgradeCost.materials.some(mat => {
                      const inventoryItem = inventory.find(inv => inv.item_id === mat.itemId);
                      return (inventoryItem?.quantity || 0) < mat.quantity;
                    })
                  }
                  className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                    crystals < upgradeCost.crystals ||
                    upgradeCost.materials.some(mat => {
                      const inventoryItem = inventory.find(inv => inv.item_id === mat.itemId);
                      return (inventoryItem?.quantity || 0) < mat.quantity;
                    })
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

        {/* Purchase Slot Modal */}
        {showPurchaseSlotModal && slotInfo && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowPurchaseSlotModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Purchase Factory Slot</h3>
              <div className="mb-4">
                <p className="text-slate-300 mb-2">Current Slots: {slotInfo.max_slots}</p>
                <p className="text-slate-300 mb-2">New Slots: {slotInfo.max_slots + 1}</p>
                <p className="text-yellow-400 font-semibold mb-2">Cost: 💎 {slotInfo.next_cost.toLocaleString()}</p>
                <p className="text-slate-400 text-sm">Allows more simultaneous production across all factories</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => setShowPurchaseSlotModal(false)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handlePurchaseSlotConfirm}
                  disabled={crystals < slotInfo.next_cost}
                  className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                    crystals < slotInfo.next_cost
                      ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                      : 'bg-blue-600 hover:bg-blue-500 text-white'
                  }`}
                >
                  Purchase
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
