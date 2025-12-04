import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'
import { useGameMessageStore } from '@/stores/useGameMessageStore'
import { getItemNameWithLevel } from '@/lib/itemUtils'

interface InventoryItem {
  player_id: string
  item_id: number
  quantity: number
}

export interface StorageUsage {
  capacity: number
  used: number
  available: number
  percentage: number
}

interface UpgradeWarehouseResult {
  success: boolean
  new_level: number
  new_capacity: number
  cost: number
}

export interface InventoryState {
  inventory: InventoryItem[]
  storageUsage: StorageUsage | null
  loading: boolean
  error: string | null
  previousInventory: InventoryItem[]
  setInventory: (inventory: InventoryItem[]) => void
  setStorageUsage: (usage: StorageUsage) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchInventory: () => Promise<void>
  fetchStorageUsage: () => Promise<void>
  upgradeWarehouse: () => Promise<void>
  subscribeToInventoryUpdates: () => () => void
}

export const useInventoryStore = create<InventoryState>((set, get) => ({
  inventory: [],
  storageUsage: null,
  loading: false,
  error: null,
  previousInventory: [] as InventoryItem[],
  setInventory: (inventory) => {
    const { previousInventory } = get();
    
    // Only show messages if this is not the initial load (previousInventory is not empty)
    // This prevents showing messages for all items when the game restarts
    if (previousInventory.length > 0) {
      // Check for new items or quantity increases
      inventory.forEach((item) => {
        const previousItem = previousInventory.find((prev) => prev.item_id === item.item_id);
        if (!previousItem) {
          // New item added
          useGameMessageStore.getState().addMessage(
            'success',
            `+${item.quantity} ${getItemNameWithLevel(item.item_id)} added to inventory!`
          );
        } else if (item.quantity > previousItem.quantity) {
          // Quantity increased
          const diff = item.quantity - previousItem.quantity;
          useGameMessageStore.getState().addMessage(
            'success',
            `+${diff} ${getItemNameWithLevel(item.item_id)} added to inventory!`
          );
        }
      });
    }
    
    set({ inventory, previousInventory: inventory, error: null });
  },
  setStorageUsage: (usage) => set({ storageUsage: usage }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchInventory: async () => {
    const { setInventory, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('inventory')
        .select('*')
        .eq('player_id', user.id)
        .gt('quantity', 0)  // Only fetch items with quantity > 0
        .order('item_id', { ascending: true })
      if (error) throw error
      setInventory(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch inventory'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  subscribeToInventoryUpdates: () => {
    const supabase = createClient()
    const channel = supabase.channel('inventory')
    channel
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'inventory'
        },
        () => {
          get().fetchInventory().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Subscribed to inventory updates')
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for inventory')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
  fetchStorageUsage: async () => {
    const { setStorageUsage, setError } = get()
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase.rpc('get_storage_usage', {
        p_player_id: user.id
      })
      if (error) throw error
      setStorageUsage(data)
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch storage usage'
      setError(errorMessage)
      handleError(err, errorMessage)
    }
  },
  upgradeWarehouse: async () => {
    const { fetchStorageUsage, fetchInventory, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('upgrade_warehouse')
      if (error) throw error
      
      const result: UpgradeWarehouseResult = data
      
      if (result.success) {
        useGameMessageStore.getState().addMessage(
          'success',
          `Warehouse upgraded to level ${result.new_level}! Capacity: ${result.new_capacity}`
        );
        await fetchStorageUsage()
        await fetchInventory()
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to upgrade warehouse'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
}))