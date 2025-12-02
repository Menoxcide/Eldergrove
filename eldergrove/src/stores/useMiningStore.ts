import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface OreType {
  id: number
  name: string
  item_id: number
  rarity: 'common' | 'rare' | 'epic'
  base_value_crystals: number
  icon: string
}

export interface MiningTool {
  id: number
  player_id: string
  tool_type: 'basic_pickaxe' | 'iron_pickaxe' | 'diamond_pickaxe' | 'magic_pickaxe'
  level: number
  durability: number
  created_at: string
}

export interface MineDig {
  id: number
  player_id: string
  depth: number
  last_dig_at: string
  total_digs: number
  artifacts: Array<{
    item_id: number
    name: string
    found_at: string
    depth: number
  }>
  energy_used_today: number
  last_energy_reset: string
}

export interface MiningState {
  mineDig: MineDig | null
  tools: MiningTool[]
  oreTypes: OreType[]
  loading: boolean
  error: string | null
  setMineDig: (dig: MineDig | null) => void
  setTools: (tools: MiningTool[]) => void
  setOreTypes: (types: OreType[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchMineDig: () => Promise<void>
  fetchTools: () => Promise<void>
  fetchOreTypes: () => Promise<void>
  mineOre: (toolType?: string) => Promise<void>
  repairTool: (toolType: string) => Promise<void>
  upgradeTool: (toolType: string) => Promise<void>
  subscribeToMining: () => () => void
}

export const useMiningStore = create<MiningState>((set, get) => ({
  mineDig: null,
  tools: [],
  oreTypes: [],
  loading: false,
  error: null,
  setMineDig: (dig) => set({ mineDig: dig, error: null }),
  setTools: (tools) => set({ tools, error: null }),
  setOreTypes: (types) => set({ oreTypes: types, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchMineDig: async () => {
    const { setMineDig, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('mine_digs')
        .select('*')
        .eq('player_id', user.id)
        .single()
      if (error && error.code !== 'PGRST116') throw error // PGRST116 = not found
      
      if (data) {
        // Parse JSONB artifacts
        const mineDig = {
          ...data,
          artifacts: typeof data.artifacts === 'string' ? JSON.parse(data.artifacts) : data.artifacts
        }
        setMineDig(mineDig)
      } else {
        setMineDig(null)
      }
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching mine dig:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchTools: async () => {
    const { setTools, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('mining_tools')
        .select('*')
        .eq('player_id', user.id)
        .order('created_at', { ascending: true })
      if (error) throw error
      setTools(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching tools:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchOreTypes: async () => {
    const { setOreTypes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('ore_types')
        .select('*')
        .order('rarity', { ascending: true })
        .order('base_value_crystals', { ascending: true })
      if (error) throw error
      setOreTypes(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching ore types:', err)
    } finally {
      setLoading(false)
    }
  },
  mineOre: async (toolType: string = 'basic_pickaxe') => {
    const { fetchMineDig, fetchTools, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('mine_ore', {
        p_tool_type: toolType
      })
      if (error) throw error

      const result = data as {
        success: boolean
        ore_found: boolean
        ore_id: number | null
        ore_name: string | null
        new_depth: number
        energy_remaining: number
        tool_durability: number
      }

      if (result.success) {
        if (result.ore_found && result.ore_name) {
          toast.success(`Found ${result.ore_name}! Depth: ${result.new_depth}`)
        } else {
          toast('No ore found this time', { icon: '⛏️' })
        }
        await fetchMineDig()
        await fetchTools()
        // Refresh inventory
        const { useInventoryStore } = await import('./useInventoryStore')
        useInventoryStore.getState().fetchInventory()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to mine: ${err.message}`)
      console.error('Error mining ore:', err)
      throw err
    }
  },
  repairTool: async (toolType: string) => {
    const { fetchTools, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('repair_tool', {
        p_tool_type: toolType
      })
      if (error) throw error
      toast.success('Tool repaired!')
      await fetchTools()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to repair tool: ${err.message}`)
      console.error('Error repairing tool:', err)
      throw err
    }
  },
  upgradeTool: async (toolType: string) => {
    const { fetchTools, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('upgrade_mining_tool', {
        p_tool_type: toolType
      })
      if (error) throw error
      toast.success('Tool upgraded!')
      await fetchTools()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to upgrade tool: ${err.message}`)
      console.error('Error upgrading tool:', err)
      throw err
    }
  },
  subscribeToMining: () => {
    const supabase = createClient()
    const channel = supabase.channel('mining')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'mine_digs' },
        () => {
          get().fetchMineDig()
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'mining_tools' },
        () => {
          get().fetchTools()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

