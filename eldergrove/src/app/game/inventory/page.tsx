'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useInventoryStore } from '@/stores/useInventoryStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { getItemIcon, getItemName, getItemCategory, getCategoryName, type ItemCategory, isSeed, isFinishedProductionItem, getCropIdFromSeed, isOre, getItemNameWithLevel, getItemIconWithAnimal, isLeveledAnimal } from '@/lib/itemUtils';
import { createClient } from '@/lib/supabase/client';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { useErrorHandler } from '@/hooks/useErrorHandler';

interface MarketplaceItem {
  item_id: number;
  sell_price_crystals: number;
  available: boolean;
}

export default function InventoryPage() {
  const router = useRouter();
  const { inventory, loading, fetchInventory, subscribeToInventoryUpdates } = useInventoryStore();
  const { crystals, setCrystals } = usePlayerStore();
  const [marketplace, setMarketplace] = useState<MarketplaceItem[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<ItemCategory | 'all'>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [showSellModal, setShowSellModal] = useState<{ itemId: number; name: string; quantity: number; price: number } | null>(null);
  const [sellQuantity, setSellQuantity] = useState<string>('1');
  const [selling, setSelling] = useState<number | null>(null);
  const { handleError, showError } = useErrorHandler();

  useEffect(() => {
    fetchInventory();
    fetchMarketplace();
    const unsubscribe = subscribeToInventoryUpdates();
    return unsubscribe;
  }, [fetchInventory, subscribeToInventoryUpdates]);

  const fetchMarketplace = async () => {
    try {
      const supabase = createClient();
      const { data, error } = await supabase
        .from('marketplace')
        .select('*')
        .eq('available', true);

      if (error) throw error;
      setMarketplace(data || []);
    } catch (error: any) {
      handleError(error, 'Failed to load marketplace prices');
    }
  };

  const getSellPrice = (itemId: number): number => {
    const item = marketplace.find(m => m.item_id === itemId);
    return item?.sell_price_crystals || 0;
  };

  const handleSell = async () => {
    if (!showSellModal) return;

    const quantity = parseInt(sellQuantity);
    if (isNaN(quantity) || quantity <= 0) {
      showError('Invalid Quantity', 'Please enter a valid quantity greater than 0.');
      return;
    }

    if (quantity > showSellModal.quantity) {
      showError('Insufficient Items', `You only have ${showSellModal.quantity.toLocaleString()} ${showSellModal.name} available.`, { itemId: showSellModal.itemId, available: showSellModal.quantity, required: quantity });
      return;
    }

    setSelling(showSellModal.itemId);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc('sell_item', {
        p_item_id: showSellModal.itemId,
        p_quantity: quantity
      });

      if (error) throw error;

      const result = data as { success: boolean; crystals_awarded: number; new_crystal_balance: number };
      
      if (result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
        useGameMessageStore.getState().addMessage(
          'success',
          `Sold ${quantity} ${showSellModal.name} for ${result.crystals_awarded} crystals!`
        );
        // Use the returned crystal balance directly to avoid race conditions
        setCrystals(result.new_crystal_balance);
        await fetchInventory();
        setShowSellModal(null);
        setSellQuantity('1');
      }
    } catch (error: any) {
      handleError(error, error.message);
    } finally {
      setSelling(null);
    }
  };

  const handlePlantSeed = async (seedItemId: number) => {
    // Seeds use item_id 100-110, need to convert to crop_id for planting
    // For now, navigate to farm - the farm page will handle seed selection
    router.push('/game/farm');
    const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
    useGameMessageStore.getState().addMessage('info', 'Navigate to Farm to plant seeds');
  };

  const handleUseInFactory = async (itemId: number) => {
    router.push('/game/factory');
    const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
    useGameMessageStore.getState().addMessage('info', 'Navigate to Factory to use items in recipes');
  };

  const handleUseInArmory = async (itemId: number) => {
    router.push('/game/armory');
    const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
    useGameMessageStore.getState().addMessage('info', 'Navigate to Armory to craft equipment');
  };

  // Filter and categorize items
  const filteredItems = inventory.filter(item => {
    // Category filter
    if (selectedCategory !== 'all') {
      const category = getItemCategory(item.item_id);
      if (category !== selectedCategory) return false;
    }

    // Search filter
    if (searchQuery) {
      const name = getItemName(item.item_id).toLowerCase();
      return name.includes(searchQuery.toLowerCase());
    }

    return true;
  });

  // Group by category
  const categorizedItems: Record<string, typeof inventory> = {};
  filteredItems.forEach(item => {
    const category = getItemCategory(item.item_id);
    if (!categorizedItems[category]) {
      categorizedItems[category] = [];
    }
    categorizedItems[category].push(item);
  });

  const categories: ItemCategory[] = ['seeds', 'crops', 'production', 'ore', 'equipment', 'other'];

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-emerald-900 via-green-900 to-teal-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Inventory</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-emerald-900 via-green-900 to-teal-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Inventory</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
          </div>
        </div>

        {/* Search and Filters */}
        <div className="mb-6 space-y-4">
          <input
            type="text"
            placeholder="Search items..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full px-4 py-2 bg-slate-800/60 text-white rounded-lg border border-slate-700 focus:border-emerald-500 focus:outline-none"
          />
          
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => setSelectedCategory('all')}
              className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                selectedCategory === 'all'
                  ? 'bg-emerald-600 text-white'
                  : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
              }`}
            >
              All
            </button>
            {categories.map(category => (
              <button
                key={category}
                onClick={() => setSelectedCategory(category)}
                className={`px-4 py-2 rounded-lg font-semibold transition-colors ${
                  selectedCategory === category
                    ? 'bg-emerald-600 text-white'
                    : 'bg-slate-700 text-slate-300 hover:bg-slate-600'
                }`}
              >
                {getCategoryName(category)}
              </button>
            ))}
          </div>
        </div>

        {/* Items by Category */}
        {filteredItems.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg">No items found</p>
            <p className="text-slate-400 mt-2">
              {searchQuery ? 'Try a different search term' : 'Your inventory is empty'}
            </p>
          </div>
        ) : (
          <div className="space-y-6">
            {categories.map(category => {
              const items = categorizedItems[category];
              if (!items || items.length === 0) return null;

              return (
                <div key={category} className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
                  <h2 className="text-xl font-bold text-white mb-4">{getCategoryName(category)}</h2>
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                    {items.map((item) => {
                      const sellPrice = getSellPrice(item.item_id);
                      const canSell = sellPrice > 0;

                      const isOreItem = isOre(item.item_id);
                      
                      return (
                        <div
                          key={item.item_id}
                          onClick={isOreItem ? () => handleUseInArmory(item.item_id) : undefined}
                          className={`bg-gradient-to-br from-slate-800 to-slate-900 rounded-xl p-4 border border-slate-700 transition-all ${
                            isOreItem ? 'hover:border-blue-500 cursor-pointer' : 'hover:border-emerald-500'
                          }`}
                        >
                          <div className="flex items-center gap-3 mb-3">
                            <span className="text-4xl">{isLeveledAnimal(item.item_id) ? getItemIconWithAnimal(item.item_id) : getItemIcon(item.item_id)}</span>
                            <div className="flex-1">
                              <div className="text-white font-semibold">{isLeveledAnimal(item.item_id) ? getItemNameWithLevel(item.item_id) : getItemName(item.item_id)}</div>
                              <div className="text-slate-400 text-sm">Qty: {item.quantity.toLocaleString()}</div>
                              {canSell && (
                                <div className="text-yellow-400 text-xs">💎 {sellPrice} each</div>
                              )}
                            </div>
                          </div>

                          <div className="flex flex-wrap gap-2">
                            {isSeed(item.item_id) && (
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handlePlantSeed(item.item_id);
                                }}
                                className="flex-1 px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg text-sm font-semibold transition-colors"
                              >
                                🌱 Plant
                              </button>
                            )}
                            {/* Crops (1-10) should only show Sell button, no Plant button */}
                            {/* Production items (11-19) should only show Sell button, no Use button */}
                            {/* Show Use in Factory for crops, Use in Armory for ores */}
                            {!isSeed(item.item_id) && 
                             !isFinishedProductionItem(item.item_id) && 
                             getItemCategory(item.item_id) === 'crops' && (
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleUseInFactory(item.item_id);
                                }}
                                className="flex-1 px-3 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-semibold transition-colors"
                              >
                                ⚙️ Use
                              </button>
                            )}
                            {!isSeed(item.item_id) && 
                             !isFinishedProductionItem(item.item_id) && 
                             getItemCategory(item.item_id) === 'ore' && (
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleUseInArmory(item.item_id);
                                }}
                                className="flex-1 px-3 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg text-sm font-semibold transition-colors"
                              >
                                ⚔️ Armory
                              </button>
                            )}
                            {canSell && (
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  setShowSellModal({
                                    itemId: item.item_id,
                                    name: getItemName(item.item_id),
                                    quantity: item.quantity,
                                    price: sellPrice
                                  });
                                }}
                                className="flex-1 px-3 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg text-sm font-semibold transition-colors"
                              >
                                💰 Sell
                              </button>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Sell Modal */}
        {showSellModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowSellModal(null)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-yellow-500/50" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Sell {showSellModal.name}</h3>
              
              <div className="mb-4">
                <div className="flex items-center gap-3 mb-4">
                  <span className="text-4xl">{getItemIcon(showSellModal.itemId)}</span>
                  <div>
                    <div className="text-white font-semibold">{showSellModal.name}</div>
                    <div className="text-slate-400 text-sm">Available: {showSellModal.quantity.toLocaleString()}</div>
                    <div className="text-yellow-400 text-sm">Price: 💎 {showSellModal.price} each</div>
                  </div>
                </div>

                <div className="flex items-center justify-between mb-2">
                  <label className="block text-white font-semibold">Quantity</label>
                  <button
                    onClick={() => setSellQuantity(showSellModal.quantity.toString())}
                    className="px-3 py-1 text-xs bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-semibold transition-colors"
                  >
                    Max
                  </button>
                </div>
                <input
                  type="number"
                  min="1"
                  max={showSellModal.quantity}
                  value={sellQuantity}
                  onChange={(e) => setSellQuantity(e.target.value)}
                  className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg border border-slate-600 focus:border-yellow-500 focus:outline-none"
                />

                <div className="mt-3 text-white">
                  <div className="text-sm text-slate-400">Total:</div>
                  <div className="text-xl font-bold text-yellow-400">
                    💎 {isNaN(parseInt(sellQuantity)) ? 0 : parseInt(sellQuantity) * showSellModal.price}
                  </div>
                </div>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => setShowSellModal(null)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleSell}
                  disabled={selling === showSellModal.itemId || parseInt(sellQuantity) <= 0 || parseInt(sellQuantity) > showSellModal.quantity}
                  className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                    selling === showSellModal.itemId || parseInt(sellQuantity) <= 0 || parseInt(sellQuantity) > showSellModal.quantity
                      ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                      : 'bg-yellow-600 hover:bg-yellow-500 text-white'
                  }`}
                >
                  {selling === showSellModal.itemId ? 'Selling...' : 'Sell'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

