import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { usePlayerStore } from './usePlayerStore'
import { handleError } from '@/hooks/useErrorHandler'

export interface QuestObjective {
  type: string
  target: number
  current?: number
  description: string
}

export interface Quest {
  id: number
  name: string
  type: 'tutorial' | 'daily' | 'weekly' | 'story'
  title: string
  description: string
  objectives: QuestObjective[]
  rewards: {
    crystals?: number
    xp?: number
    items?: Record<string, number>
  }
  order_index: number
  available: boolean
}

export interface QuestProgress {
  player_id: string
  quest_id: number
  progress: QuestObjective[]
  completed: boolean
  completed_at: string | null
  claimed: boolean
  claimed_at: string | null
  started_at: string
  expires_at: string | null
  quest?: Quest
}

export interface QuestState {
  quests: Quest[]
  playerQuests: QuestProgress[]
  loading: boolean
  error: string | null
  setQuests: (quests: Quest[]) => void
  setPlayerQuests: (quests: QuestProgress[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchQuests: () => Promise<void>
  fetchPlayerQuests: () => Promise<void>
  startQuest: (questId: number) => Promise<void>
  claimQuestReward: (questId: number) => Promise<void>
  generateDailyQuests: () => Promise<void>
  subscribeToQuests: () => () => void
}

export const useQuestStore = create<QuestState>((set, get) => ({
  quests: [],
  playerQuests: [],
  loading: false,
  error: null,
  setQuests: (quests) => set({ quests, error: null }),
  setPlayerQuests: (quests) => set({ playerQuests: quests, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchQuests: async () => {
    const { setQuests, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('quests')
        .select('*')
        .eq('available', true)
        .order('order_index', { ascending: true })
        .order('id', { ascending: true })
      if (error) throw error
      
      // Parse JSONB fields
      const quests = (data || []).map(quest => ({
        ...quest,
        objectives: typeof quest.objectives === 'string' ? JSON.parse(quest.objectives) : quest.objectives,
        rewards: typeof quest.rewards === 'string' ? JSON.parse(quest.rewards) : quest.rewards
      }))
      
      setQuests(quests)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching quests:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchPlayerQuests: async () => {
    const { setPlayerQuests, setLoading, setError, fetchQuests } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }

      await fetchQuests()
      const { quests } = get()

      const { data, error } = await supabase
        .from('quest_progress')
        .select('*')
        .eq('player_id', user.id)
        .order('started_at', { ascending: false })
      if (error) throw error

      // Parse and join with quests
      const playerQuestsWithDetails = (data || []).map(pq => ({
        ...pq,
        progress: typeof pq.progress === 'string' ? JSON.parse(pq.progress) : pq.progress,
        quest: quests.find(q => q.id === pq.quest_id)
      }))

      setPlayerQuests(playerQuestsWithDetails)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching player quests:', err)
    } finally {
      setLoading(false)
    }
  },
  startQuest: async (questId: number) => {
    const { fetchPlayerQuests, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('start_quest', {
        p_quest_id: questId
      })
      if (error) throw error
      await fetchPlayerQuests()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Quest started!')
    } catch (err: any) {
      setError(err.message)
      handleError(err, err.message)
      throw err
    }
  },
  claimQuestReward: async (questId: number) => {
    const { fetchPlayerQuests, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('claim_quest_reward', {
        p_quest_id: questId
      })
      if (error) throw error

      const result = data as { success: boolean; crystals_awarded: number; xp_awarded: number; new_crystal_balance: number }
      
      if (result.success) {
        // Use the returned crystal balance directly to avoid race conditions
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          const playerStore = usePlayerStore.getState()
          playerStore.setCrystals(result.new_crystal_balance)
        }
        
        // Refresh player profile to update XP and level (XP is granted by claim_quest_reward)
        await usePlayerStore.getState().fetchPlayerProfile()
        
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Quest completed! +${result.crystals_awarded} crystals, +${result.xp_awarded} XP`
        )
        await fetchPlayerQuests()
      }
    } catch (err: any) {
      setError(err.message)
      handleError(err, err.message)
      throw err
    }
  },
  generateDailyQuests: async () => {
    const { fetchPlayerQuests, setError } = get()
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { error } = await supabase.rpc('generate_daily_quests', {
        p_player_id: user.id
      })
      if (error) throw error
      await fetchPlayerQuests()
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Daily quests generated!')
    } catch (err: any) {
      setError(err.message)
      handleError(err, err.message)
    }
  },
  subscribeToQuests: () => {
    const supabase = createClient()
    const channel = supabase.channel('quest_progress')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'quest_progress' },
        () => {
          get().fetchPlayerQuests()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

