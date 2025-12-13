import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { playCollectSound } from '@/lib/audio'
import { handleError } from '@/hooks/useErrorHandler'
import { ITEM_NAME_TO_ID } from '@/lib/itemMappings'
import { crystalTransactionManager } from '@/lib/crystalTransactionManager'

interface Factory {
  player_id: string
  factory_type: string
  level: number
}

export interface FactoryQueueItem {
  player_id: string
  factory_type: string
  recipe_id: number
  slot: number
  started_at: string | null
  finishes_at: string
}

export interface Recipe {
  id: number
  name: string
  input: Record<string, number>
  output: Record<string, number>
  minutes: number
}

export interface FactorySlotInfo {
  current_slots_used: number
  max_slots: number
  next_cost: number
  can_add_more: boolean
}

interface PurchaseSlotResult {
  success: boolean
  cost_paid: number
  new_max_slots: number
  new_crystal_balance?: number
}

interface CollectFactoryResult {
  success: boolean
  output: Record<string, number>
  xp_gained: number
  new_crystal_balance: number
  crystals_awarded: number
}

interface UpgradeFactoryResult {
  success: boolean
  new_level: number
  unlocks_queue_slot: boolean
  new_crystal_balance?: number
}

export interface FactoryState {
  factories: Factory[]
  queue: FactoryQueueItem[]
  recipes: Recipe[]
  inventory: Array<{ item_id: number; quantity: number }>
  loading: boolean
  error: string | null
  slotInfo: FactorySlotInfo | null
  setFactories: (factories: Factory[]) => void
  setQueue: (queue: FactoryQueueItem[]) => void
  setRecipes: (recipes: Recipe[]) => void
  setInventory: (inventory: Array<{ item_id: number; quantity: number }>) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchFactories: () => Promise<void>
  fetchQueue: () => Promise<void>
  fetchRecipes: () => Promise<void>
  fetchInventory: () => Promise<void>
  getSlotInfo: () => Promise<void>
  purchaseFactorySlot: () => Promise<void>
  subscribeToQueueUpdates: () => () => void
  startProduction: (factory_type: string, recipe_name: string) => Promise<void>
  collectFactory: (slot: number) => Promise<void>
  upgradeFactory: (factoryType: string) => Promise<void>
  canCraftRecipe: (recipe: Recipe) => boolean
}

export const useFactoryStore = create<FactoryState>((set, get) => ({
  factories: [],
  queue: [],
  recipes: [],
  inventory: [],
  loading: false,
  error: null,
  slotInfo: null,
  setFactories: (factories) => set({ factories, error: null }),
  setQueue: (queue) => set({ queue, error: null }),
  setRecipes: (recipes) => set({ recipes, error: null }),
  setInventory: (inventory) => set({ inventory, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  getSlotInfo: async () => {
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('get_factory_slot_info')
      if (error) throw error
      set({ slotInfo: data })
    } catch (err: unknown) {
      handleError(err, 'Error fetching factory slot info')
    }
  },
  purchaseFactorySlot: async () => {
    const { getSlotInfo, setError } = get()

    await crystalTransactionManager.executeCrystalOperation(async () => {
      const { usePlayerStore } = await import('@/stores/usePlayerStore')
      const supabase = createClient()
      const { data, error } = await supabase.rpc('purchase_factory_slot')
      if (error) {
        throw error
      }

      const result: PurchaseSlotResult = data
      if (result.success) {
        // Update crystals from returned balance if available
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          usePlayerStore.getState().setCrystals(result.new_crystal_balance)
        }
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Purchased factory slot for ${result.cost_paid} crystals! Max slots: ${result.new_max_slots}`
        )
        await getSlotInfo()
      }
    }, 'Purchase factory slot')
  },
  fetchFactories: async () => {
    const { setFactories, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('factories')
        .select('*')
        .eq('player_id', user.id)
        .order('factory_type')
      if (error) throw error
      setFactories(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch factories'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchQueue: async () => {
    const { setQueue, setLoading, setError, getSlotInfo } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('factory_queue')
        .select('*')
        .eq('player_id', user.id)
        .order('factory_type')
        .order('slot')
      if (error) throw error
      setQueue(data || [])
      // Also fetch slot info
      await getSlotInfo()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch factory queue'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  subscribeToQueueUpdates: () => {
    const supabase = createClient()
    const channel = supabase.channel('factory_queue')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'factory_queue' },
        () => {
          get().fetchQueue().catch((err) => {
            handleError(err, 'Error in subscription callback')
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          // Subscription successful - no need to log in production
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          handleError(new Error('Subscription error for factory queue'), 'Failed to subscribe to factory queue updates')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
  startProduction: async (factory_type: string, recipe_name: string) => {
    const { fetchQueue, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('start_factory_production', {
        p_factory_type: factory_type,
        p_recipe_name: recipe_name
      })
      if (error) {
        handleError(error, `Failed to start production for ${recipe_name} in ${factory_type}`)
        throw error
      }
      await fetchQueue()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'success',
        `${recipe_name} production started!`
      )
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : `An unexpected error occurred while starting ${recipe_name} production in ${factory_type}`
      const contextualMessage = `Failed to start ${recipe_name} production in ${factory_type}: ${errorMessage}`
      setError(contextualMessage)
      handleError(err, contextualMessage)
      throw err
    }
  },
  collectFactory: async (slot: number) => {
    const { fetchQueue, setError } = get()

    await crystalTransactionManager.executeCrystalOperation(async () => {
      const { usePlayerStore } = await import('@/stores/usePlayerStore')
      const supabase = createClient()
      const { data: result, error } = await supabase.rpc('collect_factory', {
        p_slot: slot
      })
      if (error) {
        handleError(error, `Failed to collect factory slot ${slot}`)
        throw error
      }

      // Parse the jsonb response
      const collectionResult: CollectFactoryResult = result

      // Validate that the new balance is not negative
      if (collectionResult.new_crystal_balance < 0) {
        throw new Error('Collection would result in negative crystal balance')
      }
      // Update crystal balance from the response
      if (collectionResult.new_crystal_balance !== null && collectionResult.new_crystal_balance !== undefined) {
        usePlayerStore.getState().setCrystals(collectionResult.new_crystal_balance)
      }

      await fetchQueue()
      playCollectSound()

      // Create descriptive collection message similar to armory
      let collectionMessage = 'Items Collected!'
      if (collectionResult.output) {
        const { getItemName } = await import('@/lib/itemUtils')
        // Filter out crystals from output (handled separately)
        const itemEntries = Object.entries(collectionResult.output).filter(
          ([key]) => key.toLowerCase() !== 'crystals'
        )
        
        if (itemEntries.length === 1) {
          const [itemName, quantity] = itemEntries[0]
          const itemId = ITEM_NAME_TO_ID[itemName.toLowerCase()]
          if (itemId) {
            collectionMessage = `${quantity > 1 ? quantity + 'x ' : ''}${getItemName(itemId)} ${quantity > 1 ? 'Collected' : 'Collected'}!`
          }
        } else if (itemEntries.length > 1) {
          collectionMessage = `${itemEntries.length} Items Collected!`
        }
      }

      // Show visual feedback using game message system
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'collection',
        collectionMessage,
        {
          items: collectionResult.output,
          crystals: collectionResult.crystals_awarded > 0 ? collectionResult.crystals_awarded : undefined,
          xp: collectionResult.xp_gained > 0 ? collectionResult.xp_gained : undefined,
        }
      )
    }, `Collect factory slot ${slot}`)
  },
  fetchRecipes: async () => {
    const { setRecipes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('recipes')
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
          handleError(parseError, `Error parsing recipe JSON for ${recipe?.name || 'unknown recipe'}`)
          return {
            ...recipe,
            input: {},
            output: {}
          }
        }
      })
      setRecipes(recipes)
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch recipes'
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
  upgradeFactory: async (factoryType: string) => {
    const { fetchFactories, fetchInventory, setError } = get()

    await crystalTransactionManager.executeCrystalOperation(async () => {
      const { usePlayerStore } = await import('./usePlayerStore')
      const supabase = createClient()
      const { data, error } = await supabase.rpc('upgrade_factory', {
        p_factory_type: factoryType
      })
      if (error) {
        throw error
      }

      const result: UpgradeFactoryResult = data

      if (result.success) {
        // Update crystals from returned balance if available
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          usePlayerStore.getState().setCrystals(result.new_crystal_balance)
        }
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Factory upgraded to level ${result.new_level}!${result.unlocks_queue_slot ? ' New queue slot unlocked!' : ''}`
        )
        await fetchFactories()
        await fetchInventory()
      }
    }, `Upgrade factory ${factoryType}`)
  },
  canCraftRecipe: (recipe: Recipe) => {
    const { inventory } = get()

    for (const [itemName, requiredQty] of Object.entries(recipe.input)) {
      const itemId = ITEM_NAME_TO_ID[itemName.toLowerCase()]
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