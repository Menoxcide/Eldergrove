import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export const getItemName = (itemId: number): string => {
  // This is a simplified mapping - in a real app, this would come from a database or config
  const itemNames: Record<number, string> = {
    1: 'Wheat',
    2: 'Carrot',
    3: 'Potato',
    4: 'Tomato',
    5: 'Corn',
    6: 'Pumpkin',
    7: 'Minor Healing Potion',
    8: 'Bread',
    9: 'Magic Essence',
    10: 'Enchanted Seeds',
    11: 'Berry',
    12: 'Herbs',
    13: 'Magic Mushroom',
    14: 'Enchanted Flower'
  };
  return itemNames[itemId] || `Item ${itemId}`;
};

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
    
    // Check for new items or quantity increases
    inventory.forEach((item) => {
      const previousItem = previousInventory.find((prev) => prev.item_id === item.item_id);
      if (!previousItem) {
        // New item added
        toast.success(`+${item.quantity} ${getItemName(item.item_id)} added to inventory!`);
      } else if (item.quantity > previousItem.quantity) {
        // Quantity increased
        const diff = item.quantity - previousItem.quantity;
        toast.success(`+${diff} ${getItemName(item.item_id)} added to inventory!`);
      }
    });
    
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
        .order('item_id', { ascending: true })
      if (error) throw error
      setInventory(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching inventory:', err)
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
          get().fetchInventory()
        }
      )
      .subscribe()

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
      setStorageUsage(data as StorageUsage)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching storage usage:', err)
    }
  },
  upgradeWarehouse: async () => {
    const { fetchStorageUsage, fetchInventory, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('upgrade_warehouse')
      if (error) throw error
      
      const result = data as { success: boolean; new_level: number; new_capacity: number; cost: number }
      
      if (result.success) {
        toast.success(`Warehouse upgraded to level ${result.new_level}! Capacity: ${result.new_capacity}`)
        await fetchStorageUsage()
        await fetchInventory()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to upgrade warehouse: ${err.message}`)
      console.error('Error upgrading warehouse:', err)
      throw err
    }
  },
}))