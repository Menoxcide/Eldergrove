import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'

export interface PremiumShopItem {
  id: number
  item_type: 'speed_up' | 'decoration' | 'building' | 'boost' | 'bundle'
  item_id: string
  name: string
  description: string | null
  icon: string | null
  cost_aether: number
  cost_crystals: number
  available: boolean
  sort_order: number
  metadata: Record<string, any>
}

export interface PremiumShopState {
  items: PremiumShopItem[]
  loading: boolean
  error: string | null
  setItems: (items: PremiumShopItem[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchItems: () => Promise<void>
  purchaseItem: (itemId: string, useAether?: boolean) => Promise<void>
}

export const usePremiumShopStore = create<PremiumShopState>((set, get) => ({
  items: [],
  loading: false,
  error: null,
  setItems: (items) => set({ items, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchItems: async () => {
    const { setItems, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('premium_shop')
        .select('*')
        .eq('available', true)
        .order('sort_order', { ascending: true })
      if (error) throw error
      setItems(data || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching premium shop items:', err)
    } finally {
      setLoading(false)
    }
  },
  purchaseItem: async (itemId: string, useAether: boolean = true) => {
    const { fetchItems, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('purchase_premium_item', {
        p_item_id: itemId,
        p_use_aether: useAether
      })
      if (error) throw error

      const result = data as { success: boolean; item_type: string; [key: string]: any }
      
      if (result.success) {
        let message = '✅ Purchase successful!'
        
        // Handle item-specific logic
        if (result.item_type === 'speed_up') {
          message += `\n\nSpeed-up activated: ${result.minutes} minutes`
        } else if (result.item_type === 'boost') {
          message += `\n\nBoost activated for ${result.duration_hours} hours!`
        } else if (result.item_type === 'bundle') {
          message += '\n\nBundle items added to your inventory!'
        }
        
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage('success', message)
        
        // Refresh player profile to update aether/crystals
        const { usePlayerStore } = await import('./usePlayerStore')
        await usePlayerStore.getState().fetchPlayerProfile()
      }
    } catch (err: any) {
      setError(err.message)
      handleError(err, err.message)
      throw err
    }
  },
}))

