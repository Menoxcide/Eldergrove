'use client';

import { useEffect, useState } from 'react';
import FactoryQueueSlot from '@/components/game/FactoryQueueSlot';
import RecipeCard from '@/components/game/RecipeCard';
import { useFactoryStore } from '@/stores/useFactoryStore';

export default function FactoryPage() {
  const {
    factories,
    queue,
    recipes,
    inventory,
    loading,
    fetchFactories,
    fetchQueue,
    fetchRecipes,
    fetchInventory,
    startProduction,
    upgradeFactory,
    canCraftRecipe,
    subscribeToQueueUpdates
  } = useFactoryStore();
  const [selectedFactory, setSelectedFactory] = useState<string | null>(null);

  useEffect(() => {
    fetchFactories();
    fetchQueue();
    fetchRecipes();
    fetchInventory();
    const unsubscribe = subscribeToQueueUpdates();
    return unsubscribe;
  }, [fetchFactories, fetchQueue, fetchRecipes, fetchInventory, subscribeToQueueUpdates]);

  useEffect(() => {
    if (factories.length > 0 && !selectedFactory) {
      setSelectedFactory(factories[0].factory_type);
    }
  }, [factories, selectedFactory]);

  const handleStartProduction = async (recipeName: string) => {
    if (!selectedFactory) return;
    try {
      await startProduction(selectedFactory, recipeName);
      await fetchInventory(); // Refresh inventory after starting
    } catch (error) {
      // Error already handled in store
    }
  };

  const maxSlots = 2;
  const currentQueueSlots = queue.filter(q => q.factory_type === selectedFactory).length;
  const emptySlots = maxSlots - currentQueueSlots;

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

  const currentFactoryQueue = queue.filter(q => q.factory_type === selectedFactory);

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Factory</h1>

        {factories.length > 0 && (
          <div className="mb-6">
            <div className="flex gap-2 flex-wrap mb-2">
              {factories.map((factory) => (
                <button
                  key={factory.factory_type}
                  onClick={() => setSelectedFactory(factory.factory_type)}
                  className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                    selectedFactory === factory.factory_type
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                  }`}
                >
                  {factory.factory_type} (Lv.{factory.level})
                </button>
              ))}
            </div>
            {selectedFactory && (
              <div className="flex gap-2">
                <button
                  onClick={async () => {
                    if (confirm(`Upgrade ${selectedFactory}? This will cost crystals and materials.`)) {
                      try {
                        await upgradeFactory(selectedFactory);
                        await fetchFactories();
                        await fetchInventory();
                      } catch (error) {
                        // Error handled in store
                      }
                    }
                  }}
                  disabled={(factories.find(f => f.factory_type === selectedFactory)?.level ?? 0) >= 5}
                  className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                    (factories.find(f => f.factory_type === selectedFactory)?.level ?? 0) >= 5
                      ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                      : 'bg-green-600 hover:bg-green-500 text-white'
                  }`}
                >
                  {(factories.find(f => f.factory_type === selectedFactory)?.level ?? 0) >= 5
                    ? 'Max Level'
                    : `Upgrade ${selectedFactory}`}
                </button>
              </div>
            )}
          </div>
        )}

        {selectedFactory && (
          <>
            <div className="mb-6">
              <h2 className="text-xl font-bold text-white mb-4">Production Queue</h2>
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
      </div>
    </div>
  );
}
