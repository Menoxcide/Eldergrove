'use client';

import { useEffect, useState } from 'react';
import { useSkyportStore, type SkyportOrder } from '@/stores/useSkyportStore';
import { useInventoryStore, getItemName } from '@/stores/useInventoryStore';
import { getItemIcon } from '@/lib/itemUtils';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { usePlayerStore } from '@/stores/usePlayerStore';

interface OrderCardProps {
  order: SkyportOrder;
  onFulfill: (orderId: number) => void;
  inventory: Array<{ item_id: number; quantity: number }>;
}

const OrderCard: React.FC<OrderCardProps> = ({ order, onFulfill, inventory }) => {
  const [timeLeft, setTimeLeft] = useState(0);
  const [canFulfill, setCanFulfill] = useState(false);

  useEffect(() => {
    const updateTime = () => {
      const now = Date.now();
      const expiresTime = new Date(order.expires_at).getTime();
      setTimeLeft(Math.max(0, (expiresTime - now) / 1000));
    };

    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, [order.expires_at]);

  useEffect(() => {
    // Check if player has all required items
    let hasAllItems = true;
    for (const [itemIdStr, requiredQty] of Object.entries(order.requirements)) {
      const itemId = parseInt(itemIdStr);
      const inventoryItem = inventory.find(inv => inv.item_id === itemId);
      const availableQty = inventoryItem?.quantity || 0;
      if (availableQty < requiredQty) {
        hasAllItems = false;
        break;
      }
    }
    setCanFulfill(hasAllItems && timeLeft > 0);
  }, [order.requirements, inventory, timeLeft]);

  const formatTime = (seconds: number): string => {
    if (seconds <= 0) return 'Expired';
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m ${secs}s`;
  };

  const getOrderTypeIcon = (type: string): string => {
    switch (type) {
      case 'quick': return '🚁'; // Helicopter
      case 'standard': return '✈️'; // Skyport/Airplane
      case 'premium': return '🐋'; // Spirit Whale
      default: return '📦';
    }
  };

  const getOrderTypeName = (type: string): string => {
    switch (type) {
      case 'quick': return 'Quick Order';
      case 'standard': return 'Standard Order';
      case 'premium': return 'Premium Order';
      default: return 'Order';
    }
  };

  const getOrderTypeColor = (type: string): string => {
    switch (type) {
      case 'quick': return 'from-yellow-600 to-orange-600';
      case 'standard': return 'from-blue-600 to-indigo-600';
      case 'premium': return 'from-purple-600 to-pink-600';
      default: return 'from-gray-600 to-gray-700';
    }
  };

  return (
    <div className={`bg-gradient-to-br ${getOrderTypeColor(order.order_type)} rounded-2xl p-6 border-2 border-white/20 shadow-lg`}>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <span className="text-4xl">{getOrderTypeIcon(order.order_type)}</span>
          <div>
            <h3 className="text-xl font-bold text-white">{getOrderTypeName(order.order_type)}</h3>
            <p className="text-white/80 text-sm">Order #{order.id}</p>
          </div>
        </div>
        <div className="text-right">
          <div className="text-white/90 text-sm">Expires in</div>
          <div className="text-white font-mono font-bold">{formatTime(timeLeft)}</div>
        </div>
      </div>

      <div className="mb-4">
        <div className="text-white/90 text-sm mb-2 font-semibold">Required Items:</div>
        <div className="flex flex-wrap gap-2">
          {Object.entries(order.requirements).map(([itemIdStr, requiredQty]) => {
            const itemId = parseInt(itemIdStr);
            const inventoryItem = inventory.find(inv => inv.item_id === itemId);
            const availableQty = inventoryItem?.quantity || 0;
            const hasEnough = availableQty >= requiredQty;

            return (
              <div
                key={itemId}
                className={`flex items-center gap-2 px-3 py-2 rounded-lg ${
                  hasEnough ? 'bg-green-900/50' : 'bg-red-900/50'
                }`}
              >
                <span className="text-2xl">{getItemIcon(itemId)}</span>
                <div>
                  <div className={`text-sm font-semibold ${hasEnough ? 'text-white' : 'text-red-200'}`}>
                    {requiredQty} {getItemName(itemId)}
                  </div>
                  {!hasEnough && (
                    <div className="text-xs text-red-300">({availableQty} available)</div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="mb-4">
        <div className="text-white/90 text-sm mb-2 font-semibold">Rewards:</div>
        <div className="flex flex-wrap gap-3">
          {order.rewards.crystals && (
            <div className="flex items-center gap-2 px-3 py-2 bg-yellow-900/50 rounded-lg">
              <span className="text-xl">💎</span>
              <span className="text-white font-semibold">{order.rewards.crystals} Crystals</span>
            </div>
          )}
          {order.rewards.xp && (
            <div className="flex items-center gap-2 px-3 py-2 bg-blue-900/50 rounded-lg">
              <span className="text-xl">⭐</span>
              <span className="text-white font-semibold">{order.rewards.xp} XP</span>
            </div>
          )}
          {order.rewards.items && Object.entries(order.rewards.items).map(([itemIdStr, qty]) => {
            const itemId = parseInt(itemIdStr);
            return (
              <div key={itemId} className="flex items-center gap-2 px-3 py-2 bg-green-900/50 rounded-lg">
                <span className="text-xl">{getItemIcon(itemId)}</span>
                <span className="text-white font-semibold">{qty} {getItemName(itemId)}</span>
              </div>
            );
          })}
        </div>
      </div>

      <button
        onClick={() => onFulfill(order.id)}
        disabled={!canFulfill}
        className={`w-full py-3 rounded-lg font-bold text-lg transition-colors ${
          canFulfill
            ? 'bg-white text-gray-900 hover:bg-gray-100'
            : 'bg-gray-500 text-gray-300 cursor-not-allowed'
        }`}
      >
        {canFulfill ? 'Fulfill Order' : timeLeft <= 0 ? 'Expired' : 'Insufficient Items'}
      </button>
    </div>
  );
};

export default function SkyportPage() {
  const { orders, loading, fetchOrders, generateOrders, fulfillOrder, subscribeToOrders } = useSkyportStore();
  const { inventory, fetchInventory } = useInventoryStore();
  const { crystals } = usePlayerStore();

  useEffect(() => {
    fetchOrders();
    fetchInventory();
    const unsubscribe = subscribeToOrders();
    return unsubscribe;
  }, [fetchOrders, fetchInventory, subscribeToOrders]);

  const handleFulfill = async (orderId: number) => {
    try {
      await fulfillOrder(orderId);
      await fetchInventory();
    } catch (error) {
      // Error already handled in store
    }
  };

  const handleGenerateOrders = async () => {
    try {
      await generateOrders();
    } catch (error) {
      // Error already handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Skyport</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Skyport</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            <button
              onClick={handleGenerateOrders}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
            >
              Generate Orders
            </button>
          </div>
        </div>

        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20 mb-6">
          <p className="text-slate-300 text-center">
            Fulfill orders to earn crystals, XP, and special items. Orders expire, so act quickly!
          </p>
        </div>

        {orders.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg mb-4">No active orders</p>
            <p className="text-slate-400 mb-4">Click "Generate Orders" to get new orders!</p>
            <button
              onClick={handleGenerateOrders}
              className="px-6 py-3 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
            >
              Generate Orders
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {orders.map((order) => (
              <OrderCard
                key={order.id}
                order={order}
                onFulfill={handleFulfill}
                inventory={inventory}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

