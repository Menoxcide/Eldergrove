'use client';

import { useEffect } from 'react';
import { usePremiumShopStore } from '@/stores/usePremiumShopStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';

export default function PremiumShopPage() {
  const {
    items,
    loading,
    fetchItems,
    purchaseItem
  } = usePremiumShopStore();
  const { aether, crystals } = usePlayerStore();

  useEffect(() => {
    fetchItems();
  }, [fetchItems]);

  const handlePurchase = async (itemId: string, useAether: boolean) => {
    try {
      await purchaseItem(itemId, useAether);
    } catch (error) {
      // Error handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-pink-900 to-rose-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Premium Shop</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  const groupedItems = items.reduce((acc, item) => {
    if (!acc[item.item_type]) {
      acc[item.item_type] = [];
    }
    acc[item.item_type].push(item);
    return acc;
  }, {} as Record<string, typeof items>);

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-pink-900 to-rose-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Premium Shop</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-purple-800/60 rounded-lg border border-purple-500/30">
              <span className="text-2xl">✨</span>
              <span className="text-white font-mono">{aether.toLocaleString()}</span>
              <span className="text-purple-300 text-sm">Aether</span>
            </div>
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
          </div>
        </div>

        {Object.entries(groupedItems).map(([category, categoryItems]) => (
          <div key={category} className="mb-8">
            <h2 className="text-xl font-bold text-white mb-4 capitalize">
              {category.replace('_', ' ')}
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {categoryItems.map((item) => (
                <div
                  key={item.id}
                  className="bg-gradient-to-br from-purple-800 to-pink-800 rounded-xl p-6 border-2 border-purple-500/30 hover:border-purple-400/50 transition-all"
                >
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-4xl">{item.icon || '✨'}</span>
                    <div className="flex-1">
                      <h3 className="text-white font-bold text-lg">{item.name}</h3>
                      {item.description && (
                        <p className="text-purple-200 text-sm">{item.description}</p>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center justify-between mb-4">
                    {item.cost_aether > 0 && (
                      <div className="flex items-center gap-2">
                        <span className="text-purple-300 font-semibold">✨ {item.cost_aether}</span>
                        {item.cost_crystals > 0 && <span className="text-slate-400">or</span>}
                      </div>
                    )}
                    {item.cost_crystals > 0 && (
                      <div className="flex items-center gap-2">
                        <span className="text-yellow-400 font-semibold">💎 {item.cost_crystals}</span>
                      </div>
                    )}
                  </div>

                  <div className="flex gap-2">
                    {item.cost_aether > 0 && (
                      <button
                        onClick={() => handlePurchase(item.item_id, true)}
                        disabled={aether < item.cost_aether}
                        className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                          aether < item.cost_aether
                            ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                            : 'bg-purple-600 hover:bg-purple-500 text-white'
                        }`}
                      >
                        Buy with Aether
                      </button>
                    )}
                    {item.cost_crystals > 0 && (
                      <button
                        onClick={() => handlePurchase(item.item_id, false)}
                        disabled={crystals < item.cost_crystals}
                        className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                          crystals < item.cost_crystals
                            ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                            : 'bg-yellow-600 hover:bg-yellow-500 text-white'
                        }`}
                      >
                        Buy with Crystals
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}

        {items.length === 0 && (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg">No items available</p>
          </div>
        )}
      </div>
    </div>
  );
}

