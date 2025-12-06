import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'

export interface SpeedUp {
  id: number
  player_id: string
  speed_up_type: 'factory' | 'crop' | 'global' | 'armory'
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
  applyArmorySpeedUp: (armoryType: string, slot: number, minutes: number) => Promise<void>
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
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch speed-ups'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'success',
        `Speed-up applied! Production accelerated by ${minutes} minutes.`
      )
      await fetchSpeedUps()
      const { useFactoryStore } = await import('./useFactoryStore')
      useFactoryStore.getState().fetchQueue()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to apply speed-up'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'success',
        `Speed-up applied! Crop growth accelerated by ${minutes} minutes.`
      )
      await fetchSpeedUps()
      // Refresh farm plots
      const { useFarmStore } = await import('./useFarmStore')
      useFarmStore.getState().fetchPlots()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to apply speed-up'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  applyArmorySpeedUp: async (armoryType: string, slot: number, minutes: number) => {
    const { fetchSpeedUps, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('apply_armory_speed_up', {
        p_armory_type: armoryType,
        p_slot: slot,
        p_minutes: minutes
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage(
        'success',
        `Speed-up applied! Armory production accelerated by ${minutes} minutes.`
      )
      await fetchSpeedUps()
      // Refresh armory queue
      const { useArmoryStore } = await import('./useArmoryStore')
      useArmoryStore.getState().fetchQueue()
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to apply speed-up'
      setError(errorMessage)
      handleError(err, errorMessage)
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
          get().fetchSpeedUps().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for speed-ups')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

