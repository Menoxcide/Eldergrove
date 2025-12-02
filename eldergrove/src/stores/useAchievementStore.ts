import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'
import { usePlayerStore } from './usePlayerStore'

export interface Achievement {
  id: number
  name: string
  description: string
  category: 'farming' | 'factory' | 'city' | 'social' | 'general'
  condition_type: string
  condition_value: number
  reward_crystals: number
  reward_xp: number
  reward_title: string | null
  icon: string
}

export interface PlayerAchievement {
  player_id: string
  achievement_id: number
  progress: number
  completed: boolean
  completed_at: string | null
  claimed: boolean
  claimed_at: string | null
  achievement?: Achievement
}

export interface AchievementState {
  achievements: Achievement[]
  playerAchievements: PlayerAchievement[]
  loading: boolean
  error: string | null
  setAchievements: (achievements: Achievement[]) => void
  setPlayerAchievements: (achievements: PlayerAchievement[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchAchievements: () => Promise<void>
  fetchPlayerAchievements: () => Promise<void>
  claimAchievement: (achievementId: number) => Promise<void>
  subscribeToAchievements: () => () => void
}

export const useAchievementStore = create<AchievementState>((set, get) => ({
  achievements: [],
  playerAchievements: [],
  loading: false,
  error: null,
  setAchievements: (achievements) => set({ achievements, error: null }),
  setPlayerAchievements: (achievements) => set({ playerAchievements: achievements, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchAchievements: async () => {
    const { setAchievements, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('achievements')
        .select('*')
        .order('category', { ascending: true })
        .order('id', { ascending: true })
      if (error) throw error
      setAchievements(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching achievements:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchPlayerAchievements: async () => {
    const { setPlayerAchievements, setLoading, setError, fetchAchievements } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }

      // Fetch achievements first
      await fetchAchievements()
      const { achievements } = get()

      // Fetch player achievements
      const { data, error } = await supabase
        .from('player_achievements')
        .select('*')
        .eq('player_id', user.id)
        .order('achievement_id', { ascending: true })
      if (error) throw error

      // Join with achievements
      const playerAchievementsWithDetails = (data || []).map(pa => ({
        ...pa,
        achievement: achievements.find(a => a.id === pa.achievement_id)
      }))

      setPlayerAchievements(playerAchievementsWithDetails)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching player achievements:', err)
    } finally {
      setLoading(false)
    }
  },
  claimAchievement: async (achievementId: number) => {
    const { fetchPlayerAchievements, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('claim_achievement', {
        p_achievement_id: achievementId
      })
      if (error) throw error

      const result = data as { success: boolean; crystals_awarded: number; xp_awarded: number; title: string | null }
      
      if (result.success) {
        // Update player store
        const playerStore = usePlayerStore.getState()
        playerStore.addCrystals(result.crystals_awarded)
        
        toast.success(`Achievement claimed! +${result.crystals_awarded} crystals, +${result.xp_awarded} XP${result.title ? `, Title: ${result.title}` : ''}`)
        await fetchPlayerAchievements()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to claim achievement: ${err.message}`)
      console.error('Error claiming achievement:', err)
      throw err
    }
  },
  subscribeToAchievements: () => {
    const supabase = createClient()
    const channel = supabase.channel('player_achievements')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'player_achievements' },
        () => {
          get().fetchPlayerAchievements()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

