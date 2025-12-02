import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface Friend {
  id: number
  player_id: string
  friend_id: string
  status: 'pending' | 'accepted' | 'blocked'
  requested_by: string
  created_at: string
  accepted_at: string | null
  friend_profile?: {
    id: string
    username: string
    level: number
  }
}

export interface FriendHelp {
  id: number
  helper_id: string
  helped_id: string
  help_type: 'speed_production' | 'fill_order' | 'water_crops'
  target_id: number | null
  created_at: string
}

export interface FriendsState {
  friends: Friend[]
  pendingRequests: Friend[]
  loading: boolean
  error: string | null
  setFriends: (friends: Friend[]) => void
  setPendingRequests: (requests: Friend[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchFriends: () => Promise<void>
  sendFriendRequest: (friendId: string) => Promise<void>
  acceptFriendRequest: (friendId: string) => Promise<void>
  removeFriend: (friendId: string) => Promise<void>
  helpSpeedProduction: (friendId: string, factoryType: string, slot: number) => Promise<void>
  helpFillOrder: (friendId: string, orderId: number) => Promise<void>
  visitFriendTown: (friendId: string) => Promise<any>
  subscribeToFriends: () => () => void
}

export const useFriendsStore = create<FriendsState>((set, get) => ({
  friends: [],
  pendingRequests: [],
  loading: false,
  error: null,
  setFriends: (friends) => set({ friends, error: null }),
  setPendingRequests: (requests) => set({ pendingRequests: requests, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchFriends: async () => {
    const { setFriends, setPendingRequests, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }

      // Fetch accepted friends
      const { data: friendsData, error: friendsError } = await supabase
        .from('friends')
        .select(`
          *,
          friend_profile:profiles!friends_friend_id_fkey(id, username, level)
        `)
        .eq('player_id', user.id)
        .eq('status', 'accepted')
        .order('accepted_at', { ascending: false })

      if (friendsError) throw friendsError

      // Fetch pending requests (where user is the recipient)
      const { data: pendingData, error: pendingError } = await supabase
        .from('friends')
        .select(`
          *,
          friend_profile:profiles!friends_friend_id_fkey(id, username, level)
        `)
        .eq('player_id', user.id)
        .eq('status', 'pending')
        .neq('requested_by', user.id)

      if (pendingError) throw pendingError

      setFriends(friendsData || [])
      setPendingRequests(pendingData || [])
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching friends:', err)
    } finally {
      setLoading(false)
    }
  },
  sendFriendRequest: async (friendId: string) => {
    const { fetchFriends, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('send_friend_request', {
        p_friend_id: friendId
      })
      if (error) throw error
      toast.success('Friend request sent!')
      await fetchFriends()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to send friend request: ${err.message}`)
      console.error('Error sending friend request:', err)
      throw err
    }
  },
  acceptFriendRequest: async (friendId: string) => {
    const { fetchFriends, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('accept_friend_request', {
        p_friend_id: friendId
      })
      if (error) throw error
      toast.success('Friend request accepted!')
      await fetchFriends()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to accept friend request: ${err.message}`)
      console.error('Error accepting friend request:', err)
      throw err
    }
  },
  removeFriend: async (friendId: string) => {
    const { fetchFriends, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_friend', {
        p_friend_id: friendId
      })
      if (error) throw error
      toast.success('Friend removed')
      await fetchFriends()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to remove friend: ${err.message}`)
      console.error('Error removing friend:', err)
      throw err
    }
  },
  helpSpeedProduction: async (friendId: string, factoryType: string, slot: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('help_friend_speed_production', {
        p_friend_id: friendId,
        p_factory_type: factoryType,
        p_slot: slot
      })
      if (error) throw error
      toast.success('Helped friend speed up production!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to help friend: ${err.message}`)
      console.error('Error helping friend:', err)
      throw err
    }
  },
  helpFillOrder: async (friendId: string, orderId: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('help_friend_fill_order', {
        p_friend_id: friendId,
        p_order_id: orderId
      })
      if (error) throw error
      toast.success('Helped friend fill order!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to help friend: ${err.message}`)
      console.error('Error helping friend:', err)
      throw err
    }
  },
  visitFriendTown: async (friendId: string) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('visit_friend_town', {
        p_friend_id: friendId
      })
      if (error) throw error
      return data
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to visit friend town: ${err.message}`)
      console.error('Error visiting friend town:', err)
      throw err
    }
  },
  subscribeToFriends: () => {
    const supabase = createClient()
    const channel = supabase.channel('friends')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'friends' },
        () => {
          get().fetchFriends()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

