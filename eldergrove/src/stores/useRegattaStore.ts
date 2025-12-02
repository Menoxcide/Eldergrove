import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'
import { usePlayerStore } from './usePlayerStore'

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
        const regatta = {
          ...data,
          tasks: typeof data.tasks === 'string' ? JSON.parse(data.tasks) : data.tasks,
          rewards: typeof data.rewards === 'string' ? JSON.parse(data.rewards) : data.rewards
        }
        setCurrentRegatta(regatta)
      } else {
        setCurrentRegatta(null)
      }
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching current regatta:', err)
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
        const participation = {
          ...data,
          tasks_completed: typeof data.tasks_completed === 'string' ? JSON.parse(data.tasks_completed) : data.tasks_completed
        }
        setParticipation(participation)
      } else {
        setParticipation(null)
      }
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching participation:', err)
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
      setError(err.message)
      console.error('Error fetching leaderboard:', err)
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
      toast.success('Joined regatta!')
      await fetchParticipation(regattaId)
      await fetchLeaderboard(regattaId)
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to join regatta: ${err.message}`)
      console.error('Error joining regatta:', err)
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
        toast.success(`Task completed! +${result.points_awarded} points (Total: ${result.total_points})`)
        await fetchParticipation(regattaId)
        await fetchLeaderboard(regattaId)
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to submit task: ${err.message}`)
      console.error('Error submitting task:', err)
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

      const result = data as { success: boolean; rank: number; total_participants: number; crystals_awarded: number }
      
      if (result.success) {
        const playerStore = usePlayerStore.getState()
        playerStore.addCrystals(result.crystals_awarded)
        
        toast.success(`Rewards claimed! Rank: ${result.rank}/${result.total_participants}, +${result.crystals_awarded} crystals`)
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to claim rewards: ${err.message}`)
      console.error('Error claiming rewards:', err)
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
          get().fetchLeaderboard(regattaId)
          get().fetchParticipation(regattaId)
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

