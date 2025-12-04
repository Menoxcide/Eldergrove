import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'

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
  restoreEnergyWithCrystals: () => Promise<void>
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
        try {
          const mineDig = {
            ...data,
            artifacts: typeof data.artifacts === 'string' ? JSON.parse(data.artifacts) : (data.artifacts || [])
          }
          setMineDig(mineDig)
        } catch (parseError) {
          console.error('Error parsing mine dig artifacts:', parseError, data)
          const mineDig = {
            ...data,
            artifacts: []
          }
          setMineDig(mineDig)
        }
      } else {
        setMineDig(null)
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch mine dig data'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const errorMessage = err?.message || 'Failed to fetch mining tools'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const errorMessage = err?.message || 'Failed to fetch ore types'
      setError(errorMessage)
      handleError(err, errorMessage)
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

      if (result && result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        if (result.ore_found && result.ore_name) {
          useGameMessageStore.getState().addMessage(
            'success',
            `Found ${result.ore_name}! Depth: ${result.new_depth}`
          )
        } else {
          useGameMessageStore.getState().addMessage('info', 'No ore found this time')
        }
        await fetchMineDig()
        await fetchTools()
        // Refresh inventory to show collected ores
        const { useInventoryStore } = await import('./useInventoryStore')
        await useInventoryStore.getState().fetchInventory()
        // Refresh player profile to update XP and level (XP is granted by mine_ore)
        const { usePlayerStore } = await import('./usePlayerStore')
        await usePlayerStore.getState().fetchPlayerProfile()
      } else {
        throw new Error('Mining operation did not complete successfully')
      }
    } catch (err: any) {
      const errorMessage = err.message || 'An unexpected error occurred while mining'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Tool repaired!')
      await fetchTools()
      // Refresh player profile to update crystals (deducted by repair_tool RPC)
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      const errorMessage = err.message || 'An unexpected error occurred while repairing the tool'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Tool upgraded!')
      await fetchTools()
      // Refresh player profile to update crystals (deducted by upgrade_mining_tool RPC)
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      const errorMessage = err.message || 'An unexpected error occurred while upgrading the tool'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  restoreEnergyWithCrystals: async () => {
    const { fetchMineDig, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('restore_mining_energy_crystals')
      if (error) throw error

      const result = data as {
        success: boolean
        energy_restored: number
        crystals_spent: number
        new_crystals: number
        message?: string
      }

      if (result && result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Energy fully restored! (${result.energy_restored} energy restored)`
        )
        await fetchMineDig()
        // Use the returned crystal balance directly to avoid race conditions
        const { usePlayerStore } = await import('./usePlayerStore')
        usePlayerStore.getState().setCrystals(result.new_crystals)
      } else {
        const message = result?.message || 'Energy restoration failed'
        throw new Error(message)
      }
    } catch (err: any) {
      const errorMessage = err.message || 'An unexpected error occurred while restoring energy'
      setError(errorMessage)
      handleError(err, errorMessage)
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
          get().fetchMineDig().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'mining_tools' },
        () => {
          get().fetchTools().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Subscribed to mining updates')
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for mining')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

