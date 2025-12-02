import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'
import { playCollectSound } from '@/lib/audio'

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

export interface FactoryState {
  factories: Factory[]
  queue: FactoryQueueItem[]
  recipes: Recipe[]
  inventory: Array<{ item_id: number; quantity: number }>
  loading: boolean
  error: string | null
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
  setFactories: (factories) => set({ factories, error: null }),
  setQueue: (queue) => set({ queue, error: null }),
  setRecipes: (recipes) => set({ recipes, error: null }),
  setInventory: (inventory) => set({ inventory, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching factories:', err)
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
        .from('factory_queue')
        .select('*')
        .eq('player_id', user.id)
        .order('factory_type')
        .order('slot')
      if (error) throw error
      setQueue(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching factory queue:', err)
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
          get().fetchQueue()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
  startProduction: async (factory_type: string, recipe_name: string) => {
    const { fetchQueue } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('start_factory_production', {
        p_factory_type: factory_type,
        p_recipe_name: recipe_name
      })
      if (error) throw error
      await fetchQueue()
      toast.success(`${recipe_name} production started!`)
    } catch (err: any) {
      toast.error(`Failed to start production: ${err.message}`)
      console.error('Failed to start production:', err)
      throw err
    }
  },
  collectFactory: async (slot: number) => {
    const { fetchQueue } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('collect_factory', {
        p_slot: slot
      })
      if (error) throw error
      await fetchQueue()
      playCollectSound()
      toast.success('Factory output collected!')
    } catch (err: any) {
      toast.error(`Failed to collect factory output: ${err.message}`)
      console.error('Failed to collect factory output:', err)
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
        .from('recipes')
        .select('*')
        .order('id', { ascending: true })
      if (error) throw error
      // Parse JSONB fields
      const recipes = (data || []).map(recipe => ({
        ...recipe,
        input: typeof recipe.input === 'string' ? JSON.parse(recipe.input) : recipe.input,
        output: typeof recipe.output === 'string' ? JSON.parse(recipe.output) : recipe.output
      }))
      setRecipes(recipes)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching recipes:', err)
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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching inventory:', err)
    } finally {
      setLoading(false)
    }
  },
  upgradeFactory: async (factoryType: string) => {
    const { fetchFactories, fetchInventory, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('upgrade_factory', {
        p_factory_type: factoryType
      })
      if (error) throw error
      
      const result = data as { success: boolean; new_level: number; unlocks_queue_slot: boolean }
      
      if (result.success) {
        toast.success(`Factory upgraded to level ${result.new_level}!${result.unlocks_queue_slot ? ' New queue slot unlocked!' : ''}`)
        await fetchFactories()
        await fetchInventory()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to upgrade factory: ${err.message}`)
      console.error('Error upgrading factory:', err)
      throw err
    }
  },
  canCraftRecipe: (recipe: Recipe) => {
    const { inventory } = get()
    const itemNameToId: Record<string, number> = {
      'wheat': 1,
      'carrot': 2,
      'potato': 3,
      'tomato': 4,
      'corn': 5,
      'pumpkin': 6,
      'bread': 8,
      'berry': 11,
      'herbs': 12,
      'magic_mushroom': 13,
      'enchanted_flower': 14
    }

    for (const [itemName, requiredQty] of Object.entries(recipe.input)) {
      const itemId = itemNameToId[itemName.toLowerCase()]
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