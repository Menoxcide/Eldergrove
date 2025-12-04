import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'

export interface MarketListing {
  id: number
  seller_id: string
  item_id: number
  quantity: number
  price_crystals: number
  created_at: string
  expires_at: string
  purchased_at: string | null
  buyer_id: string | null
  seller_profile?: {
    id: string
    username: string
  }
}

export interface MarketBoxState {
  listings: MarketListing[]
  myListings: MarketListing[]
  loading: boolean
  error: string | null
  setListings: (listings: MarketListing[]) => void
  setMyListings: (listings: MarketListing[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchListings: () => Promise<void>
  fetchMyListings: () => Promise<void>
  createListing: (itemId: number, quantity: number, priceCrystals: number, expiresHours?: number) => Promise<void>
  purchaseListing: (listingId: number) => Promise<void>
  cancelListing: (listingId: number) => Promise<void>
  subscribeToMarketBox: () => () => void
}

export const useMarketBoxStore = create<MarketBoxState>((set, get) => ({
  listings: [],
  myListings: [],
  loading: false,
  error: null,
  setListings: (listings) => set({ listings, error: null }),
  setMyListings: (listings) => set({ myListings: listings, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchListings: async () => {
    const { setListings, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('market_listings')
        .select(`
          *,
          seller_profile:profiles!market_listings_seller_id_fkey(id, username)
        `)
        .is('purchased_at', null)
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false })
        .limit(50)
      if (error) throw error
      setListings(data || [])
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch listings'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchMyListings: async () => {
    const { setMyListings, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('market_listings')
        .select('*')
        .eq('seller_id', user.id)
        .is('purchased_at', null)
        .order('created_at', { ascending: false })
      if (error) throw error
      setMyListings(data || [])
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch my listings'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  createListing: async (itemId: number, quantity: number, priceCrystals: number, expiresHours: number = 24) => {
    const { fetchMyListings, fetchListings, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('create_listing', {
        p_item_id: itemId,
        p_quantity: quantity,
        p_price_crystals: priceCrystals,
        p_expires_hours: expiresHours
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Listing created!')
      await fetchMyListings()
      await fetchListings()
      // Refresh inventory
      const { useInventoryStore } = await import('./useInventoryStore')
      useInventoryStore.getState().fetchInventory()
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to create listing'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  purchaseListing: async (listingId: number) => {
    const { fetchListings, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('purchase_listing', {
        p_listing_id: listingId
      })
      if (error) throw error

      const result = data as { success: boolean; item_id: number; quantity: number; cost: number }
      
      if (result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'success',
          `Purchased ${result.quantity} items for ${result.cost} crystals!`
        )
        await fetchListings()
        // Refresh inventory and crystals
        const { useInventoryStore } = await import('./useInventoryStore')
        useInventoryStore.getState().fetchInventory()
        const { usePlayerStore } = await import('./usePlayerStore')
        usePlayerStore.getState().fetchPlayerProfile()
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to purchase listing'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  cancelListing: async (listingId: number) => {
    const { fetchMyListings, fetchListings, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('cancel_listing', {
        p_listing_id: listingId
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Listing cancelled! Items returned to inventory.')
      await fetchMyListings()
      await fetchListings()
      // Refresh inventory
      const { useInventoryStore } = await import('./useInventoryStore')
      useInventoryStore.getState().fetchInventory()
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to cancel listing'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  subscribeToMarketBox: () => {
    const supabase = createClient()
    const channel = supabase.channel('market_box')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'market_listings' },
        () => {
          get().fetchListings().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
          get().fetchMyListings().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Subscribed to market box updates')
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for market box')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

