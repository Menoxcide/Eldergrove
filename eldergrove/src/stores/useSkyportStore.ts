import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { usePlayerStore } from './usePlayerStore'
import { handleError } from '@/hooks/useErrorHandler'
import { crystalTransactionManager } from '@/lib/crystalTransactionManager'

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
      
      // Parse JSONB fields and filter out expired orders
      const now = new Date().getTime()
      const orders = (data || [])
        .map(order => {
          try {
            return {
              ...order,
              requirements: typeof order.requirements === 'string' ? JSON.parse(order.requirements) : order.requirements,
              rewards: typeof order.rewards === 'string' ? JSON.parse(order.rewards) : order.rewards
            }
          } catch (parseError) {
            console.error('Error parsing order JSON:', parseError, order)
            return null
          }
        })
        .filter((order): order is SkyportOrder => {
          if (!order) return false
          const expiresTime = new Date(order.expires_at).getTime()
          return !isNaN(expiresTime) && expiresTime > now
        })
      
      setOrders(orders)
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch skyport orders'
      setError(errorMessage)
      handleError(err, errorMessage)
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
      const { error, data } = await supabase.rpc('generate_skyport_orders', {
        p_player_id: user.id
      })
      if (error) {
        console.error('Error generating skyport orders:', error)
        throw error
      }
      // Fetch orders after generation
      await fetchOrders()
      const { orders } = get()
      if (orders.length === 0) {
        console.warn('No orders found after generation - may have hit limit or all expired')
      }
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'New orders generated!')
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'An unexpected error occurred while generating orders'
      console.error('Failed to generate skyport orders:', err)
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  fulfillOrder: async (orderId: number) => {
    const { fetchOrders, setError } = get()

    await crystalTransactionManager.executeCrystalOperation(async () => {
      const supabase = createClient()
      const { error, data } = await supabase.rpc('fulfill_skyport_order', {
        p_order_id: orderId
      })
      if (error) throw error

      const result = data as { success: boolean; crystals_awarded: number; xp_awarded: number; new_crystal_balance: number }

      if (result.success) {
        // Validate that the new balance is not negative
        if (result.new_crystal_balance < 0) {
          throw new Error('Transaction would result in negative crystal balance')
        }
        if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
          const playerStore = usePlayerStore.getState()
          playerStore.setCrystals(result.new_crystal_balance)
        }

        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Order fulfilled! +${result.crystals_awarded} crystals, +${result.xp_awarded} XP`
        )
        await fetchOrders()
      }
    }, `Fulfill skyport order ${orderId}`)
  },
  subscribeToOrders: () => {
    const supabase = createClient()
    const channel = supabase.channel('skyport_orders')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'skyport_orders' },
        () => {
          get().fetchOrders().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for skyport orders')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

