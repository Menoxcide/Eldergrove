import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface Building {
  id: number
  player_id: string
  building_type: string
  grid_x: number
  grid_y: number
  level: number
  created_at: string
}

export interface BuildingType {
  building_type: string
  name: string
  category: 'factory' | 'community' | 'decoration'
  base_cost_crystals: number
  size_x: number
  size_y: number
  provides_population: number
  population_required: number
  max_level: number
}

export interface CityState {
  buildings: Building[]
  buildingTypes: BuildingType[]
  loading: boolean
  error: string | null
  setBuildings: (buildings: Building[]) => void
  setBuildingTypes: (types: BuildingType[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchBuildings: () => Promise<void>
  fetchBuildingTypes: () => Promise<void>
  placeBuilding: (buildingType: string, gridX: number, gridY: number) => Promise<void>
  moveBuilding: (buildingId: number, newX: number, newY: number) => Promise<void>
  removeBuilding: (buildingId: number) => Promise<void>
  subscribeToBuildings: () => () => void
}

export const useCityStore = create<CityState>((set, get) => ({
  buildings: [],
  buildingTypes: [],
  loading: false,
  error: null,
  setBuildings: (buildings) => set({ buildings, error: null }),
  setBuildingTypes: (types) => set({ buildingTypes: types, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchBuildings: async () => {
    const { setBuildings, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('buildings')
        .select('*')
        .eq('player_id', user.id)
        .order('created_at', { ascending: true })
      if (error) throw error
      setBuildings(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching buildings:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchBuildingTypes: async () => {
    const { setBuildingTypes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      // Use RPC to get available buildings filtered by population
      const { data, error } = await supabase.rpc('get_available_buildings')
      if (error) {
        // Fallback to direct query if RPC fails
        const { data: fallbackData, error: fallbackError } = await supabase
          .from('building_types')
          .select('*')
          .order('category', { ascending: true })
          .order('base_cost_crystals', { ascending: true })
        if (fallbackError) throw fallbackError
        setBuildingTypes(fallbackData || [])
      } else {
        setBuildingTypes(data || [])
      }
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching building types:', err)
    } finally {
      setLoading(false)
    }
  },
  placeBuilding: async (buildingType: string, gridX: number, gridY: number) => {
    const { fetchBuildings, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('place_building', {
        p_building_type: buildingType,
        p_grid_x: gridX,
        p_grid_y: gridY
      })
      if (error) throw error
      toast.success('Building placed!')
      await fetchBuildings()
      // Refresh player profile to update population
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to place building: ${err.message}`)
      console.error('Error placing building:', err)
      throw err
    }
  },
  moveBuilding: async (buildingId: number, newX: number, newY: number) => {
    const { fetchBuildings, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('move_building', {
        p_building_id: buildingId,
        p_new_x: newX,
        p_new_y: newY
      })
      if (error) throw error
      await fetchBuildings()
      toast.success('Building moved successfully!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to move building: ${err.message}`)
      console.error('Error moving building:', err)
      throw err
    }
  },
  removeBuilding: async (buildingId: number) => {
    const { fetchBuildings, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_building', {
        p_building_id: buildingId
      })
      if (error) throw error
      toast.success('Building removed!')
      await fetchBuildings()
      // Refresh player profile to update population
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to remove building: ${err.message}`)
      console.error('Error removing building:', err)
      throw err
    }
  },
  subscribeToBuildings: () => {
    const supabase = createClient()
    const channel = supabase.channel('buildings')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'buildings' },
        () => {
          get().fetchBuildings()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

