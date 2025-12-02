import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface Decoration {
  id: number
  player_id: string
  decoration_type: string
  grid_x: number
  grid_y: number
  placed_at: string
}

export interface DecorationType {
  decoration_type: string
  name: string
  icon: string
  cost_crystals: number
  size_x: number
  size_y: number
  category: 'statue' | 'tree' | 'fountain' | 'other'
}

export interface DecorationsState {
  decorations: Decoration[]
  decorationTypes: DecorationType[]
  loading: boolean
  error: string | null
  setDecorations: (decorations: Decoration[]) => void
  setDecorationTypes: (types: DecorationType[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchDecorations: () => Promise<void>
  fetchDecorationTypes: () => Promise<void>
  placeDecoration: (decorationType: string, gridX: number, gridY: number) => Promise<void>
  removeDecoration: (decorationId: number) => Promise<void>
  subscribeToDecorations: () => () => void
}

export const useDecorationsStore = create<DecorationsState>((set, get) => ({
  decorations: [],
  decorationTypes: [],
  loading: false,
  error: null,
  setDecorations: (decorations) => set({ decorations, error: null }),
  setDecorationTypes: (types) => set({ decorationTypes: types, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchDecorations: async () => {
    const { setDecorations, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('decorations')
        .select('*')
        .eq('player_id', user.id)
        .order('placed_at', { ascending: true })
      if (error) throw error
      setDecorations(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching decorations:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchDecorationTypes: async () => {
    const { setDecorationTypes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('decoration_types')
        .select('*')
        .order('category', { ascending: true })
        .order('cost_crystals', { ascending: true })
      if (error) throw error
      setDecorationTypes(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching decoration types:', err)
    } finally {
      setLoading(false)
    }
  },
  placeDecoration: async (decorationType: string, gridX: number, gridY: number) => {
    const { fetchDecorations, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('place_decoration', {
        p_decoration_type: decorationType,
        p_grid_x: gridX,
        p_grid_y: gridY
      })
      if (error) throw error
      toast.success('Decoration placed!')
      await fetchDecorations()
      // Refresh player crystals
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to place decoration: ${err.message}`)
      console.error('Error placing decoration:', err)
      throw err
    }
  },
  removeDecoration: async (decorationId: number) => {
    const { fetchDecorations, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_decoration', {
        p_decoration_id: decorationId
      })
      if (error) throw error
      toast.success('Decoration removed!')
      await fetchDecorations()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to remove decoration: ${err.message}`)
      console.error('Error removing decoration:', err)
      throw err
    }
  },
  subscribeToDecorations: () => {
    const supabase = createClient()
    const channel = supabase.channel('decorations')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'decorations' },
        () => {
          get().fetchDecorations()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

