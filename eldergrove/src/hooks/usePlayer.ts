'use client'

import { useEffect } from 'react'
import { usePlayerStore } from '@/stores/usePlayerStore'
import { createClient } from '@/lib/supabase/client'
import type { RealtimePostgresChangesPayload } from '@supabase/supabase-js'

export const usePlayer = () => {
  const { id, setPlayer, setLoading, claimDailyReward } = usePlayerStore()

  useEffect(() => {
    if (id) return

    let isMounted = true

    const fetchProfile = async () => {
      setLoading(true)

      try {
        const supabase = createClient()
        const { data: { user } } = await supabase.auth.getUser()

        if (user && isMounted) {
          const { data, error } = await supabase
            .from('profiles')
            .select('id, username, crystals, level, xp, population, town_size, aether')
            .eq('id', user.id)
            .single()

          if (error) throw error

          setPlayer(data, true) // Ignore realtime guard for manual fetches
          
          // Automatically claim daily reward when player loads
          await claimDailyReward()
        } else if (isMounted) {
          setPlayer(null)
        }
      } catch (error) {
        console.error('Error fetching profile:', error)
        if (isMounted) {
          setPlayer(null)
        }
      } finally {
        if (isMounted) {
          setLoading(false)
        }
      }
    }

    fetchProfile()

    return () => {
      isMounted = false
    }
  }, [id, setPlayer, setLoading, claimDailyReward])

  // Set up realtime subscription for profile updates (XP, level, crystals, etc.)
  useEffect(() => {
    if (!id) return

    const supabase = createClient()
    
    // Subscribe to changes in the profiles table for this user
    const channel = supabase
      .channel(`profile-changes-${id}`)
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'profiles',
          filter: `id=eq.${id}`,
        },
        (payload: RealtimePostgresChangesPayload<Record<string, unknown>>) => {
          const newData = payload.new
          if (newData && typeof newData === 'object' && 'id' in newData) {
            setPlayer({
              id: newData.id as string,
              username: newData.username as string,
              crystals: newData.crystals as number,
              level: newData.level as number,
              xp: newData.xp as number,
              population: newData.population as number,
              town_size: newData.town_size as number,
              aether: newData.aether as number,
            })
          }
        }
      )
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR') {
          console.error('Error subscribing to profile changes')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [id, setPlayer])
}