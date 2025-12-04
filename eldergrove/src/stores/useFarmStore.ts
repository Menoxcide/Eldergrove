import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { get, set } from 'idb-keyval'
import { playPlantSound, playHarvestSound } from '@/lib/audio'
import { handleError } from '@/hooks/useErrorHandler'

interface FarmPlot {
  player_id: string
  plot_index: number
  crop_id: number | null
  planted_at: string | null
  ready_at: string | null
}

export interface Crop {
  id: number
  name: string
  grow_minutes: number
  yield_crystals: number
  item_id: number
}

export interface SeedShopItem {
  crop_id: number
  price_crystals: number
  available: boolean
  crop?: Crop
}

const QUEUE_KEY = 'eldergrove-offline-queue'

function isNetworkError(error: unknown): boolean {
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    return true
  }
  if (error instanceof Error) {
    const msg = error.message.toLowerCase()
    return (
      msg.includes('fetch') ||
      msg.includes('network') ||
      msg.includes('failed to execute') ||
      error.name === 'TypeError' ||
      error.name === 'AbortError'
    )
  }
  return false
}

export interface FarmState {
  plots: FarmPlot[]
  crops: Crop[]
  seedShop: SeedShopItem[]
  loading: boolean
  error: string | null
  setPlots: (plots: FarmPlot[]) => void
  setCrops: (crops: Crop[]) => void
  setSeedShop: (seedShop: SeedShopItem[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchPlots: () => Promise<void>
  fetchCrops: () => Promise<void>
  fetchSeedShop: () => Promise<void>
  plantCrop: (plot_index: number, crop_id: number) => Promise<void>
  harvestCrop: (plot_index: number) => Promise<void>
  buySeed: (crop_id: number) => Promise<void>
}

export const useFarmStore = create<FarmState>((set, get) => ({
  plots: [],
  crops: [],
  seedShop: [],
  loading: false,
  error: null,
  setPlots: (plots) => set({ plots, error: null }),
  setCrops: (crops) => set({ crops, error: null }),
  setSeedShop: (seedShop) => set({ seedShop, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchPlots: async () => {
    const { setPlots, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('farm_plots')
        .select('*')
        .eq('player_id', user.id)
        .order('plot_index', { ascending: true })
      if (error) throw error
      setPlots(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch farm plots'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  plantCrop: async (plot_index: number, crop_id: number) => {
    const { setError, fetchPlots } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('plant_crop', {
        p_plot_index: plot_index,
        p_crop_id: crop_id
      })
      if (error) {
        throw error
      }
      
      const { useInventoryStore } = await import('./useInventoryStore')
      await useInventoryStore.getState().fetchInventory()
      
      await fetchPlots()
      playPlantSound()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Crop planted successfully!')
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to plant crop'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  harvestCrop: async (plot_index: number) => {
    const { setError, fetchPlots } = get()
    try {
      const supabase = createClient()
      const { data: newCrystals, error } = await supabase.rpc('harvest_plot', {
        p_plot_index: plot_index
      })
      if (error) {
        throw error
      }

      const { useInventoryStore } = await import('./useInventoryStore')
      await useInventoryStore.getState().fetchInventory()

      const { usePlayerStore } = await import('./usePlayerStore')
      if (newCrystals !== null && newCrystals !== undefined) {
        usePlayerStore.getState().setCrystals(newCrystals as number)
      }
      await usePlayerStore.getState().fetchPlayerProfile()

      await fetchPlots()

      playHarvestSound()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Crop harvested successfully!')
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to harvest crop'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  fetchCrops: async () => {
    const { setCrops, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('crops')
        .select('*')
        .order('id', { ascending: true })
      if (error) throw error
      setCrops(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch crops'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchSeedShop: async () => {
    const { setSeedShop, setLoading, setError, fetchCrops } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      
      // Fetch seed shop items
      const { data: seedShopData, error: seedShopError } = await supabase
        .from('seed_shop')
        .select('*')
        .eq('available', true)
        .order('crop_id', { ascending: true })
      if (seedShopError) throw seedShopError

      // Fetch crops to join with seed shop
      await fetchCrops()
      const { crops } = get()
      
      // Join seed shop with crop data
      const seedShopWithCrops = (seedShopData || []).map(shopItem => ({
        ...shopItem,
        crop: crops.find(c => c.id === shopItem.crop_id)
      }))
      
      setSeedShop(seedShopWithCrops)
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch seed shop'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  buySeed: async (crop_id: number) => {
    const { setError, seedShop } = get()
    try {
      // Get seed price for immediate UI update
      const seedItem = seedShop.find(item => item.crop_id === crop_id)
      const seedPrice = seedItem?.price_crystals || 0
      
      const supabase = createClient()
      
      // Get current crystals before purchase for calculation
      const { usePlayerStore } = await import('@/stores/usePlayerStore')
      const playerStore = usePlayerStore.getState()
      const currentCrystals = playerStore.crystals
      
      const { data: newCrystals, error } = await supabase.rpc('buy_seed', {
        p_crop_id: crop_id
      })
      if (error) {
        throw error
      }
      
      if (newCrystals !== null && newCrystals !== undefined) {
        playerStore.setCrystals(newCrystals as number)
      }
      
      const { useInventoryStore } = await import('./useInventoryStore')
      await useInventoryStore.getState().fetchInventory()
      
      const { crops } = get()
      const crop = crops.find(c => c.id === crop_id)
      const seedItemId = crop ? 100 + crop.item_id : null
      
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      if (seedItemId) {
        useGameMessageStore.getState().addMessage(
          'success',
          'Seed purchased successfully!',
          { itemIds: { [seedItemId]: 1 } }
        )
      } else {
        useGameMessageStore.getState().addMessage('success', 'Seed purchased successfully!')
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to purchase seed'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
}))