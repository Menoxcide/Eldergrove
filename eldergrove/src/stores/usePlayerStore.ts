import { create } from 'zustand'
import { claimDailyReward, DailyRewardResponse } from '@/lib/supabase/dailyReward'

interface PlayerProfile {
  id: string
  username: string
  crystals: number
  level: number
  xp: number
  population?: number
  town_size?: number
  aether?: number
}

interface PlayerState {
  id: string | null
  username: string | null
  crystals: number
  level: number
  xp: number
  population: number
  townSize: number
  aether: number
  loading: boolean
  error: string | null
  setPlayer: (profile: PlayerProfile | null) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  addCrystals: (amount: number) => void
  removeCrystals: (amount: number) => void
  setPopulation: (population: number) => void
  setTownSize: (size: number) => void
  fetchPlayerProfile: () => Promise<void>
  expandTown: (direction?: string) => Promise<void>
  getExpansionCost: (direction?: string) => Promise<number>
  claimDailyReward: () => Promise<DailyRewardResponse>
}

export const usePlayerStore = create<PlayerState>((set, get) => ({
  id: null,
  username: null,
  crystals: 500,
  level: 1,
  xp: 0,
  population: 0,
  townSize: 10,
  aether: 0,
  loading: false,
  error: null,
  setPlayer: (profile) => set({
    id: profile?.id ?? null,
    username: profile?.username ?? null,
    crystals: profile?.crystals ?? 500,
    level: profile?.level ?? 1,
    xp: profile?.xp ?? 0,
    population: profile?.population ?? 0,
    townSize: profile?.town_size ?? 10,
    aether: profile?.aether ?? 0,
  }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  addCrystals: (amount) => set((state) => ({
    crystals: state.crystals + amount
  })),
  removeCrystals: (amount) => set((state) => ({
    crystals: Math.max(0, state.crystals - amount)
  })),
  setPopulation: (population) => set({ population }),
  setTownSize: (size) => set({ townSize: size }),
  expandTown: async (direction: string = 'all') => {
    const { fetchPlayerProfile, setError } = get()
    try {
      const { createClient } = await import('@/lib/supabase/client')
      const supabase = createClient()
      const { data, error } = await supabase.rpc('expand_town', {
        p_direction: direction
      })
      if (error) throw error
      
      const result = data as { success: boolean; old_size: number; new_size: number; cost_crystals: number }
      
      if (result.success) {
        await fetchPlayerProfile()
        const { toast } = await import('react-hot-toast')
        toast.success(`Town expanded to ${result.new_size}x${result.new_size}!`)
      }
    } catch (err: any) {
      console.error('Error expanding town:', err)
      const { toast } = await import('react-hot-toast')
      toast.error(`Failed to expand town: ${err.message}`)
      throw err
    }
  },
  getExpansionCost: async (direction: string = 'all') => {
    try {
      const { createClient } = await import('@/lib/supabase/client')
      const supabase = createClient()
      const { data, error } = await supabase.rpc('get_expansion_cost', {
        p_direction: direction
      })
      if (error) throw error
      return data as number
    } catch (err: any) {
      console.error('Error getting expansion cost:', err)
      return 0
    }
  },
  fetchPlayerProfile: async () => {
    const { setPlayer, setLoading } = get()
    setLoading(true)
    try {
      const { createClient } = await import('@/lib/supabase/client')
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, crystals, level, xp, population, town_size, aether')
        .eq('id', user.id)
        .single()
      if (error) throw error
      setPlayer(data)
    } catch (err: any) {
      console.error('Error fetching player profile:', err)
    } finally {
      setLoading(false)
    }
  },
  claimDailyReward: async () => {
    const response = await claimDailyReward();
    
    // If successful and reward was awarded, update crystals in store
    if (response.success && response.crystalsAwarded && !response.alreadyClaimed) {
      set((state) => ({
        crystals: state.crystals + response.crystalsAwarded!
      }));
    }
    
    return response;
  }
}))