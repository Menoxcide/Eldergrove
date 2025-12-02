'use client'

import { useEffect } from 'react'
import { usePlayerStore } from '@/stores/usePlayerStore'
import { createClient } from '@/lib/supabase/client'

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
            .select('id, username, crystals, level, xp')
            .eq('id', user.id)
            .single()

          if (error) throw error

          setPlayer(data)
          
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
}