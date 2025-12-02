import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { get, set } from 'idb-keyval'
import toast from 'react-hot-toast'
import { playPlantSound, playHarvestSound } from '@/lib/audio'

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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching farm plots:', err)
    } finally {
      setLoading(false)
    }
  },
  plantCrop: async (plot_index: number, crop_id: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('plant_crop', {
        p_plot_index: plot_index,
        p_crop_id: crop_id
      })
      if (error) throw error
      playPlantSound()
      toast.success('Crop planted successfully!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to plant crop: ${err.message}`)
      console.error('Planting error:', err)
    }
  },
  harvestCrop: async (plot_index: number) => {
    const { setError, plots, setPlots } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('harvest_plot', {
        p_plot_index: plot_index
      })
      if (error) throw error

      // Update only the harvested plot locally to avoid full refresh
      const updatedPlots = plots.map(plot =>
        plot.plot_index === plot_index
          ? { ...plot, crop_id: null, planted_at: null, ready_at: null }
          : plot
      )
      setPlots(updatedPlots)

      playHarvestSound()
      toast.success('Crop harvested successfully!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to harvest crop: ${err.message}`)
      console.error('Harvesting error:', err)
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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching crops:', err)
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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching seed shop:', err)
    } finally {
      setLoading(false)
    }
  },
  buySeed: async (crop_id: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { data: newCrystals, error } = await supabase.rpc('buy_seed', {
        p_crop_id: crop_id
      })
      if (error) throw error
      
      // Refresh player profile to update crystals
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data: profile } = await supabase
          .from('profiles')
          .select('id, username, crystals, level, xp')
          .eq('id', user.id)
          .single()
        if (profile) {
          const { usePlayerStore } = await import('@/stores/usePlayerStore')
          usePlayerStore.getState().setPlayer(profile)
        }
      }
      
      toast.success('Seed purchased successfully!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to buy seed: ${err.message}`)
      console.error('Buy seed error:', err)
      throw err
    }
  },
}))