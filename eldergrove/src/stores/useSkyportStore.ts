import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'
import { usePlayerStore } from './usePlayerStore'

export interface SkyportOrder {
  id: number
  player_id: string
  order_type: 'quick' | 'standard' | 'premium'
  requirements: Record<string, number> // item_id: quantity
  rewards: {
    crystals?: number
    xp?: number
    items?: Record<string, number>
  }
  expires_at: string
  completed_at: string | null
  created_at: string
}

export interface SkyportState {
  orders: SkyportOrder[]
  loading: boolean
  error: string | null
  setOrders: (orders: SkyportOrder[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchOrders: () => Promise<void>
  generateOrders: () => Promise<void>
  fulfillOrder: (orderId: number) => Promise<void>
  subscribeToOrders: () => () => void
}

export const useSkyportStore = create<SkyportState>((set, get) => ({
  orders: [],
  loading: false,
  error: null,
  setOrders: (orders) => set({ orders, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchOrders: async () => {
    const { setOrders, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('skyport_orders')
        .select('*')
        .eq('player_id', user.id)
        .is('completed_at', null)
        .order('created_at', { ascending: true })
      if (error) throw error
      
      // Parse JSONB fields
      const orders = (data || []).map(order => ({
        ...order,
        requirements: typeof order.requirements === 'string' ? JSON.parse(order.requirements) : order.requirements,
        rewards: typeof order.rewards === 'string' ? JSON.parse(order.rewards) : order.rewards
      }))
      
      setOrders(orders)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching skyport orders:', err)
    } finally {
      setLoading(false)
    }
  },
  generateOrders: async () => {
    const { fetchOrders, setError } = get()
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { error } = await supabase.rpc('generate_skyport_orders', {
        p_player_id: user.id
      })
      if (error) throw error
      await fetchOrders()
      toast.success('New orders generated!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to generate orders: ${err.message}`)
      console.error('Error generating orders:', err)
    }
  },
  fulfillOrder: async (orderId: number) => {
    const { fetchOrders, setError } = get()
    try {
      const supabase = createClient()
      const { error, data } = await supabase.rpc('fulfill_skyport_order', {
        p_order_id: orderId
      })
      if (error) throw error
      
      const result = data as { success: boolean; crystals_awarded: number; xp_awarded: number }
      
      if (result.success) {
        // Update player store
        const playerStore = usePlayerStore.getState()
        playerStore.addCrystals(result.crystals_awarded)
        
        toast.success(`Order fulfilled! +${result.crystals_awarded} crystals, +${result.xp_awarded} XP`)
        await fetchOrders()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to fulfill order: ${err.message}`)
      console.error('Error fulfilling order:', err)
      throw err
    }
  },
  subscribeToOrders: () => {
    const supabase = createClient()
    const channel = supabase.channel('skyport_orders')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'skyport_orders' },
        () => {
          get().fetchOrders()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

