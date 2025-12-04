'use client';

import { useEffect, useState } from 'react';
import { useMarketBoxStore } from '@/stores/useMarketBoxStore';
import { useInventoryStore } from '@/stores/useInventoryStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { getItemIcon, getItemName } from '@/lib/itemUtils';
import { useErrorHandler } from '@/hooks/useErrorHandler';

export default function MarketBoxPage() {
  const {
    listings,
    myListings,
    loading,
    fetchListings,
    fetchMyListings,
    createListing,
    purchaseListing,
    cancelListing,
    subscribeToMarketBox
  } = useMarketBoxStore();
  const { inventory } = useInventoryStore();
  const { crystals } = usePlayerStore();
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedItem, setSelectedItem] = useState<{ item_id: number; quantity: number } | null>(null);
  const [price, setPrice] = useState('');
  const [quantity, setQuantity] = useState('');
  const { showError } = useErrorHandler();

  useEffect(() => {
    fetchListings();
    fetchMyListings();
    const unsubscribe = subscribeToMarketBox();
    return unsubscribe;
  }, [fetchListings, fetchMyListings, subscribeToMarketBox]);

  const handleCreateListing = async () => {
    if (!selectedItem || !price || !quantity) {
      showError('Missing Information', 'Please fill in all fields (item, quantity, and price).');
      return;
    }
    const priceNum = parseInt(price);
    const qtyNum = parseInt(quantity);
    if (isNaN(priceNum) || priceNum <= 0) {
      showError('Invalid Price', 'Price must be a positive number.');
      return;
    }
    if (isNaN(qtyNum) || qtyNum <= 0 || qtyNum > selectedItem.quantity) {
      showError('Invalid Quantity', `Quantity must be between 1 and ${selectedItem.quantity.toLocaleString()}.`, { itemId: selectedItem.item_id, available: selectedItem.quantity, required: qtyNum });
      return;
    }
    try {
      await createListing(selectedItem.item_id, qtyNum, priceNum);
      setShowCreateModal(false);
      setSelectedItem(null);
      setPrice('');
      setQuantity('');
    } catch (error) {
      // Error handled in store
    }
  };

  const handlePurchase = async (listingId: number) => {
    if (confirm('Purchase this listing?')) {
      try {
        await purchaseListing(listingId);
      } catch (error) {
        // Error handled in store
      }
    }
  };

  const handleCancel = async (listingId: number) => {
    if (confirm('Cancel this listing? Items will be returned to your inventory.')) {
      try {
        await cancelListing(listingId);
      } catch (error) {
        // Error handled in store
      }
    }
  };

  const formatTimeLeft = (expiresAt: string): string => {
    const now = Date.now();
    const expires = new Date(expiresAt).getTime();
    const diff = expires - now;
    if (diff <= 0) return 'Expired';
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    return `${hours}h ${minutes}m`;
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Market Box</h1>
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
          <h1 className="text-3xl font-bold text-white">Market Box</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            <button
              onClick={() => setShowCreateModal(true)}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
            >
              + Create Listing
            </button>
          </div>
        </div>

        {/* My Listings */}
        {myListings.length > 0 && (
          <div className="mb-8">
            <h2 className="text-xl font-bold text-white mb-4">My Listings</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {myListings.map((listing) => (
                <div
                  key={listing.id}
                  className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-xl p-4 border border-green-500/30"
                >
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-4xl">{getItemIcon(listing.item_id)}</span>
                    <div className="flex-1">
                      <div className="text-white font-semibold">{getItemName(listing.item_id)}</div>
                      <div className="text-green-300 text-sm">Qty: {listing.quantity}</div>
                    </div>
                  </div>
                  <div className="flex items-center justify-between mb-3">
                    <div className="text-yellow-400 font-semibold">💎 {listing.price_crystals}</div>
                    <div className="text-slate-400 text-xs">{formatTimeLeft(listing.expires_at)}</div>
                  </div>
                  <button
                    onClick={() => handleCancel(listing.id)}
                    className="w-full px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold transition-colors"
                  >
                    Cancel Listing
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Available Listings */}
        <div>
          <h2 className="text-xl font-bold text-white mb-4">Available Listings</h2>
          {listings.length === 0 ? (
            <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
              <p className="text-slate-300 text-lg">No listings available</p>
              <p className="text-slate-400 mt-2">Be the first to create a listing!</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {listings.map((listing) => (
                <div
                  key={listing.id}
                  className="bg-gradient-to-br from-blue-900 to-indigo-900 rounded-xl p-4 border border-blue-500/30"
                >
                  <div className="flex items-center gap-3 mb-3">
                    <span className="text-4xl">{getItemIcon(listing.item_id)}</span>
                    <div className="flex-1">
                      <div className="text-white font-semibold">{getItemName(listing.item_id)}</div>
                      <div className="text-blue-300 text-sm">Qty: {listing.quantity}</div>
                      <div className="text-slate-400 text-xs">by {listing.seller_profile?.username || 'Unknown'}</div>
                    </div>
                  </div>
                  <div className="flex items-center justify-between mb-3">
                    <div className="text-yellow-400 font-semibold">💎 {listing.price_crystals}</div>
                    <div className="text-slate-400 text-xs">{formatTimeLeft(listing.expires_at)}</div>
                  </div>
                  <button
                    onClick={() => handlePurchase(listing.id)}
                    disabled={crystals < listing.price_crystals}
                    className={`w-full px-4 py-2 rounded-lg font-semibold transition-colors ${
                      crystals < listing.price_crystals
                        ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                        : 'bg-green-600 hover:bg-green-500 text-white'
                    }`}
                  >
                    {crystals < listing.price_crystals ? 'Insufficient Crystals' : 'Purchase'}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Create Listing Modal */}
        {showCreateModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCreateModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Create Listing</h3>
              
              {!selectedItem ? (
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {inventory.filter(item => item.quantity > 0).map((item) => (
                    <button
                      key={item.item_id}
                      onClick={() => setSelectedItem(item)}
                      className="w-full flex items-center gap-3 p-3 bg-slate-700 hover:bg-slate-600 rounded-lg transition-colors"
                    >
                      <span className="text-3xl">{getItemIcon(item.item_id)}</span>
                      <div className="flex-1 text-left">
                        <div className="text-white font-semibold">{getItemName(item.item_id)}</div>
                        <div className="text-slate-400 text-sm">Available: {item.quantity}</div>
                      </div>
                    </button>
                  ))}
                </div>
              ) : (
                <div className="space-y-4">
                  <div className="flex items-center gap-3 p-3 bg-slate-700 rounded-lg">
                    <span className="text-4xl">{getItemIcon(selectedItem.item_id)}</span>
                    <div>
                      <div className="text-white font-semibold">{getItemName(selectedItem.item_id)}</div>
                      <div className="text-slate-400 text-sm">Available: {selectedItem.quantity}</div>
                    </div>
                  </div>
                  
                  <div>
                    <label className="text-white text-sm mb-1 block">Quantity</label>
                    <input
                      type="number"
                      value={quantity}
                      onChange={(e) => setQuantity(e.target.value)}
                      min="1"
                      max={selectedItem.quantity}
                      className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg"
                    />
                  </div>
                  
                  <div>
                    <label className="text-white text-sm mb-1 block">Price (Crystals)</label>
                    <input
                      type="number"
                      value={price}
                      onChange={(e) => setPrice(e.target.value)}
                      min="1"
                      className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg"
                    />
                  </div>
                  
                  <div className="flex gap-2">
                    <button
                      onClick={() => {
                        setSelectedItem(null);
                        setPrice('');
                        setQuantity('');
                      }}
                      className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                    >
                      Back
                    </button>
                    <button
                      onClick={handleCreateListing}
                      className="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
                    >
                      Create Listing
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

