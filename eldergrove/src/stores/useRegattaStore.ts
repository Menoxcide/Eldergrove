import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { usePlayerStore } from './usePlayerStore'
import { handleError } from '@/hooks/useErrorHandler'

export interface RegattaTask {
  type: string
  target: number
  item?: string
  points: number
}

export interface RegattaEvent {
  id: number
  name: string
  start_date: string
  end_date: string
  tasks: RegattaTask[]
  rewards: {
    top_10?: { crystals: number }
    top_25?: { crystals: number }
    participation?: { crystals: number }
  }
  status: 'upcoming' | 'active' | 'completed'
  created_at: string
}

export interface RegattaParticipant {
  regatta_id: number
  player_id: string
  coven_id: string | null
  points: number
  tasks_completed: number[]
  joined_at: string
  player_profile?: {
    id: string
    username: string
  }
}

export interface RegattaState {
  currentRegatta: RegattaEvent | null
  participation: RegattaParticipant | null
  leaderboard: Array<{
    player_id?: string
    username?: string
    coven_id?: string
    coven_name?: string
    total_points?: number
    member_count?: number
    points?: number
  }>
  covenLeaderboard: Array<{
    coven_id: string
    coven_name: string
    total_points: number
    member_count: number
  }>
  loading: boolean
  error: string | null
  setCurrentRegatta: (regatta: RegattaEvent | null) => void
  setParticipation: (participation: RegattaParticipant | null) => void
  setLeaderboard: (leaderboard: any[]) => void
  setCovenLeaderboard: (leaderboard: any[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchCurrentRegatta: () => Promise<void>
  fetchParticipation: (regattaId: number) => Promise<void>
  fetchLeaderboard: (regattaId: number, type?: 'global' | 'coven') => Promise<void>
  joinRegatta: (regattaId: number) => Promise<void>
  submitTask: (regattaId: number, taskIndex: number) => Promise<void>
  claimRewards: (regattaId: number) => Promise<void>
  subscribeToRegatta: (regattaId: number) => () => void
}

export const useRegattaStore = create<RegattaState>((set, get) => ({
  currentRegatta: null,
  participation: null,
  leaderboard: [],
  covenLeaderboard: [],
  loading: false,
  error: null,
  setCurrentRegatta: (regatta) => set({ currentRegatta: regatta, error: null }),
  setParticipation: (participation) => set({ participation, error: null }),
  setLeaderboard: (leaderboard) => set({ leaderboard, error: null }),
  setCovenLeaderboard: (leaderboard) => set({ covenLeaderboard: leaderboard, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchCurrentRegatta: async () => {
    const { setCurrentRegatta, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('regatta_events')
        .select('*')
        .in('status', ['upcoming', 'active'])
        .order('start_date', { ascending: true })
        .limit(1)
        .single()
      if (error && error.code !== 'PGRST116') throw error // PGRST116 = not found
      
      if (data) {
        try {
          const regatta = {
            ...data,
            tasks: typeof data.tasks === 'string' ? JSON.parse(data.tasks) : (data.tasks || []),
            rewards: typeof data.rewards === 'string' ? JSON.parse(data.rewards) : (data.rewards || {})
          }
          setCurrentRegatta(regatta)
        } catch (parseError) {
          console.error('Error parsing regatta JSON:', parseError, data)
          setCurrentRegatta(null)
          throw new Error('Failed to parse regatta data')
        }
      } else {
        setCurrentRegatta(null)
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch current regatta'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchParticipation: async (regattaId: number) => {
    const { setParticipation, setError } = get()
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('regatta_participants')
        .select(`
          *,
          player_profile:profiles!regatta_participants_player_id_fkey(id, username)
        `)
        .eq('regatta_id', regattaId)
        .eq('player_id', user.id)
        .single()
      if (error && error.code !== 'PGRST116') throw error
      
      if (data) {
        try {
          const participation = {
            ...data,
            tasks_completed: typeof data.tasks_completed === 'string' ? JSON.parse(data.tasks_completed) : (data.tasks_completed || [])
          }
          setParticipation(participation)
        } catch (parseError) {
          console.error('Error parsing participation JSON:', parseError, data)
          setParticipation(null)
        }
      } else {
        setParticipation(null)
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch participation'
      setError(errorMessage)
      handleError(err, errorMessage)
    }
  },
  fetchLeaderboard: async (regattaId: number, type: 'global' | 'coven' = 'global') => {
    const { setLeaderboard, setCovenLeaderboard, setError } = get()
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('get_regatta_leaderboard', {
        p_regatta_id: regattaId,
        p_leaderboard_type: type
      })
      if (error) throw error
      
      if (type === 'coven') {
        setCovenLeaderboard(data || [])
      } else {
        setLeaderboard(data || [])
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch leaderboard'
      setError(errorMessage)
      handleError(err, errorMessage)
    }
  },
  joinRegatta: async (regattaId: number) => {
    const { fetchParticipation, fetchLeaderboard, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('join_regatta', {
        p_regatta_id: regattaId
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Joined regatta!')
      await fetchParticipation(regattaId)
      await fetchLeaderboard(regattaId)
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to join regatta'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  submitTask: async (regattaId: number, taskIndex: number) => {
    const { fetchParticipation, fetchLeaderboard, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('submit_regatta_task', {
        p_regatta_id: regattaId,
        p_task_index: taskIndex
      })
      if (error) throw error

      const result = data as { success: boolean; points_awarded: number; total_points: number }
      
      if (result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Task completed! +${result.points_awarded} points (Total: ${result.total_points})`
        )
        await fetchParticipation(regattaId)
        await fetchLeaderboard(regattaId)
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to submit task'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  claimRewards: async (regattaId: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('claim_regatta_rewards', {
        p_regatta_id: regattaId
      })
      if (error) throw error

      const result = data as { success: boolean; rank: number; total_participants: number; crystals_awarded: number; new_crystal_balance: number }
      
      if (result.success) {
        // Use the returned crystal balance directly to avoid race conditions
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          const playerStore = usePlayerStore.getState()
          playerStore.setCrystals(result.new_crystal_balance)
        }
        
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Rewards claimed! Rank: ${result.rank}/${result.total_participants}, +${result.crystals_awarded} crystals`
        )
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to claim rewards'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  subscribeToRegatta: (regattaId: number) => {
    const supabase = createClient()
    const channel = supabase.channel(`regatta_${regattaId}`)
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'regatta_participants', filter: `regatta_id=eq.${regattaId}` },
        () => {
          get().fetchLeaderboard(regattaId).catch((err) => {
            console.error('Error in subscription callback:', err)
          })
          get().fetchParticipation(regattaId).catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log(`Subscribed to regatta ${regattaId} updates`)
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error(`Subscription error for regatta ${regattaId}`)
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

