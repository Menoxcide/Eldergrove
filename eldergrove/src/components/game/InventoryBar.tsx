'use client'

import { useEffect, useState } from 'react'
import { useInventoryStore } from '@/stores/useInventoryStore'
import { getItemIcon } from '@/lib/itemUtils'
import { usePlayerStore } from '@/stores/usePlayerStore'
import { Skeleton } from '@/components/ui/LoadingSkeleton'
import { createClient } from '@/lib/supabase/client'
import Tooltip from '@/components/ui/Tooltip'
import { getItemTooltip } from '@/lib/tooltipUtils'

const InventoryBar = () => {
  const { inventory, storageUsage, loading, error, fetchInventory, fetchStorageUsage, upgradeWarehouse, subscribeToInventoryUpdates } = useInventoryStore()
  const { crystals } = usePlayerStore()
  const [warehouseLevel, setWarehouseLevel] = useState<number>(1)
  const [upgradeCost, setUpgradeCost] = useState<number>(0)
  const [showUpgradeModal, setShowUpgradeModal] = useState(false)

  useEffect(() => {
    fetchInventory().catch(console.error)
    fetchStorageUsage().catch(console.error)
    const unsubscribe = subscribeToInventoryUpdates()
    
    // Fetch warehouse level
    const fetchWarehouseLevel = async () => {
      try {
        const supabase = createClient()
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          const { data } = await supabase
            .from('warehouse_upgrades')
            .select('level')
            .eq('player_id', user.id)
            .single()
          if (data) {
            setWarehouseLevel(data.level)
            setUpgradeCost(100 * (data.level + 1) * (data.level + 1))
          }
        }
      } catch (error) {
        console.error('Error fetching warehouse level:', error)
      }
    }
    fetchWarehouseLevel()
    
    return unsubscribe
  }, [fetchInventory, fetchStorageUsage, subscribeToInventoryUpdates])

  const handleUpgrade = async () => {
    try {
      await upgradeWarehouse()
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data } = await supabase
          .from('warehouse_upgrades')
          .select('level')
          .eq('player_id', user.id)
          .single()
        if (data) {
          setWarehouseLevel(data.level)
          setUpgradeCost(100 * (data.level + 1) * (data.level + 1))
        }
      }
      setShowUpgradeModal(false)
    } catch {
      // Error handled in store
    }
  }

  if (loading) {
    return (
      <div className="flex items-center gap-4 p-4 bg-gradient-to-r from-emerald-900 via-green-900/50 to-emerald-900 rounded-2xl shadow-2xl border border-emerald-500/30 backdrop-blur-md h-20 overflow-hidden">
        <Skeleton className="flex-1 h-12" />
        <Skeleton className="w-20 h-12" />
        <Skeleton className="flex-1 h-12" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-4 text-red-400 bg-red-900/50 rounded-xl border border-red-500/50">
        Error loading inventory: {error}
      </div>
    )
  }

  const storagePercentage = storageUsage ? storageUsage.percentage : 0
  const isStorageFull = storageUsage && storageUsage.used >= storageUsage.capacity

  return (
    <>
      <div className="flex flex-col gap-2 p-4 bg-gradient-to-r from-emerald-900 via-green-900/50 to-emerald-900 rounded-2xl shadow-2xl border border-emerald-500/30 backdrop-blur-md">
        {/* Storage Bar */}
        <div className="flex items-center justify-between gap-4 mb-2">
          <div className="flex items-center gap-2">
            <span className="text-sm text-slate-300">Storage:</span>
            <span className={`text-sm font-semibold ${isStorageFull ? 'text-red-400' : 'text-white'}`}>
              {storageUsage ? `${storageUsage.used}/${storageUsage.capacity}` : 'Loading...'}
            </span>
            <span className="text-xs text-slate-400">(Lv.{warehouseLevel})</span>
          </div>
          <button
            onClick={() => setShowUpgradeModal(true)}
            disabled={warehouseLevel >= 10}
            className={`px-3 py-1 rounded-lg text-xs font-semibold transition-colors ${
              warehouseLevel >= 10
                ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                : 'bg-blue-600 hover:bg-blue-500 text-white'
            }`}
          >
            Upgrade
          </button>
        </div>
        <div className="w-full bg-slate-800/60 rounded-full h-2 overflow-hidden">
          <div
            className={`h-full transition-all duration-300 ${
              isStorageFull ? 'bg-red-500' : storagePercentage > 80 ? 'bg-yellow-500' : 'bg-green-500'
            }`}
            style={{ width: `${Math.min(storagePercentage, 100)}%` }}
          />
        </div>

        {/* Inventory Items */}
        <div className="flex items-center flex-wrap gap-3 overflow-x-auto scrollbar-thin scrollbar-thumb-slate-600 scrollbar-track-slate-900/50">
          {inventory.map((item) => (
            <Tooltip
              key={item.item_id}
              content={getItemTooltip(item.item_id, item.quantity, storageUsage || undefined)}
              position="bottom"
            >
              <div className="flex items-center space-x-2 min-w-fit px-3 py-2 bg-slate-800/40 hover:bg-slate-700/60 rounded-xl transition-all duration-200 text-sm md:text-base font-mono whitespace-nowrap border border-slate-700/50 cursor-default">
                <span className="text-xl md:text-2xl flex-shrink-0">{getItemIcon(item.item_id)}</span>
                <span>{item.quantity.toLocaleString()}</span>
              </div>
            </Tooltip>
          ))}
          {inventory.length === 0 && (
            <div className="px-4 py-2 text-slate-400 italic text-sm md:text-base">No items in inventory</div>
          )}
        </div>
      </div>

      {/* Upgrade Modal */}
      {showUpgradeModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowUpgradeModal(false)}>
          <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-2xl font-bold text-white mb-4">Upgrade Warehouse</h3>
            <div className="mb-4">
              <p className="text-slate-300 mb-2">Current Level: {warehouseLevel}</p>
              <p className="text-slate-300 mb-2">Current Capacity: {storageUsage?.capacity || 50}</p>
              <p className="text-slate-300 mb-2">New Level: {warehouseLevel + 1}</p>
              <p className="text-slate-300 mb-2">New Capacity: {50 + warehouseLevel * 25}</p>
              <p className="text-yellow-400 font-semibold">Cost: 💎 {upgradeCost.toLocaleString()}</p>
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => setShowUpgradeModal(false)}
                className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleUpgrade}
                disabled={crystals < upgradeCost || warehouseLevel >= 10}
                className={`flex-1 px-4 py-2 rounded-lg font-semibold transition-colors ${
                  crystals < upgradeCost || warehouseLevel >= 10
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
    </>
  )
}

export default InventoryBar