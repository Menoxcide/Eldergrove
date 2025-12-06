import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { playCollectSound } from '@/lib/audio'
import { handleError } from '@/hooks/useErrorHandler'

interface Armory {
  player_id: string
  armory_type: string
  level: number
}

export interface ArmoryQueueItem {
  player_id: string
  armory_type: string
  recipe_id: number
  slot: number
  started_at: string | null
  finishes_at: string
}

export interface ArmoryRecipe {
  id: number
  name: string
  input: Record<string, number>
  output: Record<string, number>
  minutes: number
  armory_type: string
}

export interface ArmoryState {
  armories: Armory[]
  queue: ArmoryQueueItem[]
  recipes: ArmoryRecipe[]
  inventory: Array<{ item_id: number; quantity: number }>
  loading: boolean
  error: string | null
  setArmories: (armories: Armory[]) => void
  setQueue: (queue: ArmoryQueueItem[]) => void
  setRecipes: (recipes: ArmoryRecipe[]) => void
  setInventory: (inventory: Array<{ item_id: number; quantity: number }>) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchArmories: () => Promise<void>
  fetchQueue: () => Promise<void>
  fetchRecipes: () => Promise<void>
  fetchInventory: () => Promise<void>
  subscribeToQueueUpdates: () => () => void
  startCraft: (armory_type: string, recipe_name: string) => Promise<void>
  collectArmory: (slot: number) => Promise<void>
  upgradeArmory: (armoryType: string) => Promise<void>
  canCraftRecipe: (recipe: ArmoryRecipe) => boolean
}

export const useArmoryStore = create<ArmoryState>((set, get) => ({
  armories: [],
  queue: [],
  recipes: [],
  inventory: [],
  loading: false,
  error: null,
  setArmories: (armories) => set({ armories, error: null }),
  setQueue: (queue) => set({ queue, error: null }),
  setRecipes: (recipes) => set({ recipes, error: null }),
  setInventory: (inventory) => set({ inventory, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchArmories: async () => {
    const { setArmories, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('armories')
        .select('*')
        .eq('player_id', user.id)
        .order('armory_type')
      if (error) throw error
      setArmories(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch armories'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchQueue: async () => {
    const { setQueue, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('armory_queue')
        .select('*')
        .eq('player_id', user.id)
        .order('armory_type')
        .order('slot')
      if (error) throw error
      setQueue(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch armory queue'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  subscribeToQueueUpdates: () => {
    const supabase = createClient()
    const channel = supabase.channel('armory_queue')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'armory_queue' },
        () => {
          get().fetchQueue().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for armory queue')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
  startCraft: async (armory_type: string, recipe_name: string) => {
    const { fetchQueue, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('start_armory_craft', {
        p_armory_type: armory_type,
        p_recipe_name: recipe_name
      })
      if (error) throw error
      await fetchQueue()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'success',
        `${recipe_name} crafting started!`
      )
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'An unexpected error occurred while starting craft'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  collectArmory: async (slot: number) => {
    const { fetchQueue, setError } = get()
    try {
      const supabase = createClient()
      const { data: result, error } = await supabase.rpc('collect_armory', {
        p_slot: slot
      })
      if (error) throw error
      
      // Parse the jsonb response
      const collectionResult = result as {
        success: boolean
        output: Record<string, number>
        xp_gained: number
      }
      
      await fetchQueue()
      playCollectSound()

      // Create descriptive collection message
      let collectionMessage = 'Equipment Collected!'
      if (collectionResult.output) {
        const outputEntries = Object.entries(collectionResult.output)
        if (outputEntries.length === 1) {
          const [itemName, quantity] = outputEntries[0]
          const { getItemName } = await import('@/lib/itemUtils')
          // Map armory output names to item IDs
          const itemNameToId: Record<string, number> = {
            'iron_sword': 30,
            'steel_blade': 31,
            'diamond_armor': 32,
            'mithril_sword': 33,
            'aether_blade': 34,
            'dragon_scale_armor': 35,
            'ancient_relic_weapon': 36
          }
          const itemId = itemNameToId[itemName.toLowerCase()]
          if (itemId) {
            collectionMessage = `${quantity > 1 ? quantity + 'x ' : ''}${getItemName(itemId)} ${quantity > 1 ? 'Collected' : 'Collected'}!`
          }
        } else if (outputEntries.length > 1) {
          collectionMessage = `${outputEntries.length} Equipment Items Collected!`
        }
      }

      // Convert output items to itemIds format for proper display
      const itemIds: Record<string, number> = {}
      if (collectionResult.output) {
        const itemNameToId: Record<string, number> = {
          'iron_sword': 30,
          'steel_blade': 31,
          'diamond_armor': 32,
          'mithril_sword': 33,
          'aether_blade': 34,
          'dragon_scale_armor': 35,
          'ancient_relic_weapon': 36
        }
        Object.entries(collectionResult.output).forEach(([itemName, quantity]) => {
          const itemId = itemNameToId[itemName.toLowerCase()]
          if (itemId) {
            itemIds[itemId.toString()] = quantity
          }
        })
      }

      // Show visual feedback
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'collection',
        collectionMessage,
        {
          itemIds: itemIds,
          xp: collectionResult.xp_gained > 0 ? collectionResult.xp_gained : undefined,
        }
      )

      const { useInventoryStore } = await import('@/stores/useInventoryStore')
      await useInventoryStore.getState().fetchInventory()

      const { usePlayerStore } = await import('@/stores/usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'An unexpected error occurred while collecting equipment'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  fetchRecipes: async () => {
    const { setRecipes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('armory_recipes')
        .select('*')
        .order('id', { ascending: true })
      if (error) throw error
      // Parse JSONB fields
      const recipes = (data || []).map(recipe => {
        try {
          return {
            ...recipe,
            input: typeof recipe.input === 'string' ? JSON.parse(recipe.input) : recipe.input,
            output: typeof recipe.output === 'string' ? JSON.parse(recipe.output) : recipe.output
          }
        } catch (parseError) {
          console.error('Error parsing recipe JSON:', parseError, recipe)
          return {
            ...recipe,
            input: {},
            output: {}
          }
        }
      })
      setRecipes(recipes)
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch armory recipes'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
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
        .select('item_id, quantity')
        .eq('player_id', user.id)
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
  upgradeArmory: async (armoryType: string) => {
    const { fetchArmories, fetchInventory, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('upgrade_armory', {
        p_armory_type: armoryType
      })
      if (error) throw error
      
      const result = data as { success: boolean; new_level: number; cost: number; new_crystal_balance?: number }
      
      if (result.success) {
        // Update crystals from returned balance if available
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          const { usePlayerStore } = await import('@/stores/usePlayerStore')
          usePlayerStore.getState().setCrystals(result.new_crystal_balance)
        }
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Armory upgraded to level ${result.new_level}!`
        )
        await fetchArmories()
        await fetchInventory()
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'An unexpected error occurred while upgrading the armory'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  canCraftRecipe: (recipe: ArmoryRecipe) => {
    const { inventory } = get()
    const oreNameToId: Record<string, number> = {
      'coal': 20,
      'iron_ore': 21,
      'copper_ore': 22,
      'silver_ore': 23,
      'gold_ore': 24,
      'crystal_shard': 25,
      'mithril_ore': 26,
      'aether_crystal': 27,
      'dragon_scale': 28,
      'ancient_relic': 29
    }

    for (const [oreName, requiredQty] of Object.entries(recipe.input)) {
      const itemId = oreNameToId[oreName.toLowerCase()]
      if (!itemId) return false
      
      const inventoryItem = inventory.find(inv => inv.item_id === itemId)
      const availableQty = inventoryItem?.quantity || 0
      
      if (availableQty < requiredQty) {
        return false
      }
    }
    return true
  },
}))

