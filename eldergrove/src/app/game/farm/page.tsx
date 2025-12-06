'use client';

import { useEffect, useState } from 'react';
import CropField from '@/components/game/CropField';
import { useFarmStore } from '@/stores/useFarmStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { getItemIcon } from '@/lib/itemUtils';
import { createClient } from '@/lib/supabase/client';

export default function FarmPage() {
  const { plots, seedShop, loading, fetchPlots, fetchSeedShop, buySeed } = useFarmStore();
  const { crystals } = usePlayerStore();
  const [showSeedShop, setShowSeedShop] = useState(false);

  useEffect(() => {
    fetchPlots();
    fetchSeedShop();

    const supabase = createClient();
    const channel = supabase.channel('farm_plots_realtime');
    channel
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'farm_plots',
        },
        () => {
          fetchPlots();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [fetchPlots, fetchSeedShop]);

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Farm</h1>
          <div className="flex justify-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-500"></div>
          </div>
        </div>
      </div>
    );
  }

  const handleBuySeed = async (cropId: number) => {
    await buySeed(cropId);
    await fetchSeedShop();
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Farm</h1>
          <button
            onClick={() => setShowSeedShop(!showSeedShop)}
            className="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-semibold transition-colors"
          >
            {showSeedShop ? 'Hide' : 'Show'} Seed Shop
          </button>
        </div>

        {showSeedShop && (
          <div className="mb-6 bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
            <h2 className="text-2xl font-bold text-white mb-4">Seed Shop</h2>
            <div className="flex items-center gap-2 mb-4">
              <span className="text-xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()} Crystals</span>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4">
              {seedShop.map((item) => (
                <div
                  key={item.crop_id}
                  className="bg-slate-800/60 rounded-xl p-4 border border-slate-700/50"
                >
                  <div className="text-4xl mb-2 text-center">
                    {item.crop ? getItemIcon(item.crop.item_id) : '🌱'}
                  </div>
                  <div className="text-white font-semibold text-sm mb-2 text-center">
                    {item.crop?.name || `Crop ${item.crop_id}`}
                  </div>
                  <div className="text-yellow-400 text-xs mb-3 text-center">
                    💎 {item.price_crystals}
                  </div>
                  <button
                    onClick={() => handleBuySeed(item.crop_id)}
                    disabled={crystals < item.price_crystals}
                    className={`w-full py-2 rounded-lg font-semibold text-sm transition-colors ${
                      crystals < item.price_crystals
                        ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                        : 'bg-green-600 hover:bg-green-500 text-white'
                    }`}
                  >
                    Buy Seed
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {plots.length > 0 ? (
            plots.map((plot) => (
              <CropField key={plot.plot_index} plot={plot} />
            ))
          ) : (
            <div className="col-span-full bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
              <p className="text-slate-300 text-lg">No farm plots available</p>
              <p className="text-slate-400 mt-2">Your farm plots will appear here!</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
