import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'

export interface Road {
  id: number
  player_id: string
  grid_x: number
  grid_y: number
  road_type: 'straight_h' | 'straight_v' | 'corner_ne' | 'corner_nw' | 'corner_se' | 'corner_sw' | 'intersection' | 't_n' | 't_s' | 't_e' | 't_w'
  created_at: string
}

export interface RoadsState {
  roads: Road[]
  loading: boolean
  error: string | null
  setRoads: (roads: Road[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchRoads: () => Promise<void>
  placeRoad: (gridX: number, gridY: number) => Promise<void>
  removeRoad: (gridX: number, gridY: number) => Promise<void>
  recalculateAllRoadTypes: () => Promise<void>
  subscribeToRoads: () => () => void
}

export const useRoadsStore = create<RoadsState>((set, get) => ({
  roads: [],
  loading: false,
  error: null,
  setRoads: (roads) => set({ roads, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchRoads: async () => {
    const { setRoads, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('roads')
        .select('*')
        .eq('player_id', user.id)
        .order('created_at', { ascending: true })
      if (error) throw error
      setRoads(data || [])
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch roads'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  placeRoad: async (gridX: number, gridY: number) => {
    const { fetchRoads, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('place_road', {
        p_grid_x: gridX,
        p_grid_y: gridY
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Road placed!')
      await fetchRoads()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to place road'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  removeRoad: async (gridX: number, gridY: number) => {
    const { fetchRoads, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_road', {
        p_grid_x: gridX,
        p_grid_y: gridY
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Road removed!')
      await fetchRoads()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to remove road'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  recalculateAllRoadTypes: async () => {
    const { fetchRoads, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('recalculate_all_road_types')
      if (error) throw error
      await fetchRoads()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to recalculate road types'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  subscribeToRoads: () => {
    const supabase = createClient()
    const channel = supabase.channel('roads')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'roads' },
        () => {
          get().fetchRoads()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

