import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface SpeedUp {
  id: number
  player_id: string
  speed_up_type: 'factory' | 'crop' | 'global'
  target_id: number | null
  minutes: number
  used_at: string
  expires_at: string | null
}

export interface SpeedUpsState {
  speedUps: SpeedUp[]
  loading: boolean
  error: string | null
  setSpeedUps: (speedUps: SpeedUp[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchSpeedUps: () => Promise<void>
  applyFactorySpeedUp: (factoryType: string, slot: number, minutes: number) => Promise<void>
  applyCropSpeedUp: (plotIndex: number, minutes: number) => Promise<void>
  subscribeToSpeedUps: () => () => void
}

export const useSpeedUpsStore = create<SpeedUpsState>((set, get) => ({
  speedUps: [],
  loading: false,
  error: null,
  setSpeedUps: (speedUps) => set({ speedUps, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchSpeedUps: async () => {
    const { setSpeedUps, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('speed_ups')
        .select('*')
        .eq('player_id', user.id)
        .or('expires_at.is.null,expires_at.gt.now()') // Only active speed-ups
        .order('used_at', { ascending: false })
      if (error) throw error
      setSpeedUps(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching speed-ups:', err)
    } finally {
      setLoading(false)
    }
  },
  applyFactorySpeedUp: async (factoryType: string, slot: number, minutes: number) => {
    const { fetchSpeedUps, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('apply_factory_speed_up', {
        p_factory_type: factoryType,
        p_slot: slot,
        p_minutes: minutes
      })
      if (error) throw error
      toast.success(`Speed-up applied! Production accelerated by ${minutes} minutes.`)
      await fetchSpeedUps()
      // Refresh factory queue
      const { useFactoryStore } = await import('./useFactoryStore')
      useFactoryStore.getState().fetchQueue()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to apply speed-up: ${err.message}`)
      console.error('Error applying speed-up:', err)
      throw err
    }
  },
  applyCropSpeedUp: async (plotIndex: number, minutes: number) => {
    const { fetchSpeedUps, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('apply_crop_speed_up', {
        p_plot_index: plotIndex,
        p_minutes: minutes
      })
      if (error) throw error
      toast.success(`Speed-up applied! Crop growth accelerated by ${minutes} minutes.`)
      await fetchSpeedUps()
      // Refresh farm plots
      const { useFarmStore } = await import('./useFarmStore')
      useFarmStore.getState().fetchPlots()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to apply speed-up: ${err.message}`)
      console.error('Error applying speed-up:', err)
      throw err
    }
  },
  subscribeToSpeedUps: () => {
    const supabase = createClient()
    const channel = supabase.channel('speed_ups')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'speed_ups' },
        () => {
          get().fetchSpeedUps()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

