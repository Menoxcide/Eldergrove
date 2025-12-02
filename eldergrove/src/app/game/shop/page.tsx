'use client';

import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useInventoryStore, getItemName } from '@/stores/useInventoryStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { getItemIcon } from '@/lib/itemUtils';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import toast from 'react-hot-toast';

interface MarketplaceItem {
  item_id: number;
  sell_price_crystals: number;
  available: boolean;
}

export default function ShopPage() {
  const { inventory, fetchInventory } = useInventoryStore();
  const { crystals, addCrystals } = usePlayerStore();
  const [marketplace, setMarketplace] = useState<MarketplaceItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [selling, setSelling] = useState<number | null>(null);
  const [sellQuantity, setSellQuantity] = useState<Record<number, number>>({});

  useEffect(() => {
    fetchMarketplace();
    fetchInventory();
  }, []);

  const fetchMarketplace = async () => {
    try {
      const supabase = createClient();
      const { data, error } = await supabase
        .from('marketplace')
        .select('*')
        .eq('available', true)
        .order('item_id', { ascending: true });
      
      if (error) throw error;
      setMarketplace(data || []);
    } catch (error: any) {
      console.error('Error fetching marketplace:', error);
      toast.error('Failed to load marketplace');
    } finally {
      setLoading(false);
    }
  };

  const handleSell = async (itemId: number, quantity: number) => {
    if (quantity <= 0) {
      toast.error('Quantity must be greater than 0');
      return;
    }

    setSelling(itemId);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc('sell_item', {
        p_item_id: itemId,
        p_quantity: quantity
      });

      if (error) throw error;

      const result = data as { success: boolean; crystals_awarded: number; new_crystal_balance: number };
      
      if (result.success) {
        toast.success(`Sold ${quantity} ${getItemName(itemId)} for ${result.crystals_awarded} crystals!`);
        addCrystals(result.crystals_awarded);
        await fetchInventory();
        setSellQuantity(prev => ({ ...prev, [itemId]: 0 }));
      }
    } catch (error: any) {
      toast.error(`Failed to sell: ${error.message}`);
    } finally {
      setSelling(null);
    }
  };

  const getInventoryQuantity = (itemId: number): number => {
    const item = inventory.find(inv => inv.item_id === itemId);
    return item?.quantity || 0;
  };

  const getSellPrice = (itemId: number): number => {
    const item = marketplace.find(m => m.item_id === itemId);
    return item?.sell_price_crystals || 0;
  };

  const sellableItems = inventory.filter(inv => {
    const price = getSellPrice(inv.item_id);
    return price > 0 && inv.quantity > 0;
  });

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Marketplace</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Marketplace</h1>
          <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
            <span className="text-2xl">💎</span>
            <span className="text-white font-mono text-lg">{crystals.toLocaleString()} Crystals</span>
          </div>
        </div>

        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20 mb-6">
          <p className="text-slate-300 text-center">
            Sell your items for crystals. Prices are set by the market.
          </p>
        </div>

        {sellableItems.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg">No items available to sell</p>
            <p className="text-slate-400 mt-2">Harvest crops or craft items to sell them here!</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {sellableItems.map((item) => {
              const quantity = item.quantity;
              const price = getSellPrice(item.item_id);
              const currentSellQty = sellQuantity[item.item_id] || 1;
              const maxSell = Math.min(quantity, 100); // Limit to reasonable amounts
              const totalPrice = price * currentSellQty;

              return (
                <div
                  key={item.item_id}
                  className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20"
                >
                  <div className="flex items-center gap-4 mb-4">
                    <span className="text-5xl">{getItemIcon(item.item_id)}</span>
                    <div className="flex-1">
                      <h3 className="text-xl font-bold text-white">{getItemName(item.item_id)}</h3>
                      <p className="text-slate-300 text-sm">You have: {quantity.toLocaleString()}</p>
                    </div>
                  </div>

                  <div className="mb-4">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-slate-300">Price per unit:</span>
                      <span className="text-yellow-400 font-mono">💎 {price}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-slate-300">Total:</span>
                      <span className="text-yellow-400 font-mono font-bold">💎 {totalPrice}</span>
                    </div>
                  </div>

                  <div className="mb-4">
                    <label className="block text-slate-300 text-sm mb-2">Quantity to sell:</label>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => setSellQuantity(prev => ({
                          ...prev,
                          [item.item_id]: Math.max(1, (prev[item.item_id] || 1) - 1)
                        }))}
                        className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded-lg"
                      >
                        -
                      </button>
                      <input
                        type="number"
                        min="1"
                        max={maxSell}
                        value={currentSellQty}
                        onChange={(e) => {
                          const val = Math.max(1, Math.min(maxSell, parseInt(e.target.value) || 1));
                          setSellQuantity(prev => ({ ...prev, [item.item_id]: val }));
                        }}
                        className="flex-1 px-3 py-1 bg-slate-800 text-white rounded-lg text-center"
                      />
                      <button
                        onClick={() => setSellQuantity(prev => ({
                          ...prev,
                          [item.item_id]: Math.min(maxSell, (prev[item.item_id] || 1) + 1)
                        }))}
                        className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white rounded-lg"
                      >
                        +
                      </button>
                    </div>
                  </div>

                  <button
                    onClick={() => handleSell(item.item_id, currentSellQty)}
                    disabled={selling === item.item_id || currentSellQty > quantity}
                    className={`w-full py-2 rounded-lg font-semibold transition-colors ${
                      selling === item.item_id || currentSellQty > quantity
                        ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                        : 'bg-green-600 hover:bg-green-500 text-white'
                    }`}
                  >
                    {selling === item.item_id ? 'Selling...' : `Sell ${currentSellQty} for 💎 ${totalPrice}`}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

