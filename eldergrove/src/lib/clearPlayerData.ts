/**
 * Utility to clear all player data and cache
 * Clears IndexedDB, localStorage, and optionally Supabase data
 */

import { clear } from 'idb-keyval'
import { createClient } from '@/lib/supabase/client'

const QUEUE_KEY = 'eldergrove-offline-queue'

/**
 * Clear all IndexedDB data
 */
export async function clearIndexedDB(): Promise<void> {
  try {
    // Clear the offline queue
    await clear()
    console.log('[clearPlayerData] IndexedDB cleared')
  } catch (error) {
    console.error('[clearPlayerData] Error clearing IndexedDB:', error)
    throw error
  }
}

/**
 * Clear all localStorage data
 */
export function clearLocalStorage(): void {
  try {
    localStorage.clear()
    console.log('[clearPlayerData] localStorage cleared')
  } catch (error) {
    console.error('[clearPlayerData] Error clearing localStorage:', error)
    throw error
  }
}

/**
 * Clear all Supabase data for the current player (buildings, roads, decorations)
 * Note: This does NOT clear the player profile itself
 */
export async function clearSupabaseData(): Promise<void> {
  try {
    const supabase = createClient()
    const { data: { user } } = await supabase.auth.getUser()
    
    if (!user) {
      throw new Error('User not authenticated')
    }

    // Delete all buildings, roads, and decorations for this player
    const [buildingsResult, roadsResult, decorationsResult] = await Promise.all([
      supabase
        .from('buildings')
        .delete()
        .eq('player_id', user.id),
      supabase
        .from('roads')
        .delete()
        .eq('player_id', user.id),
      supabase
        .from('decorations')
        .delete()
        .eq('player_id', user.id),
    ])

    if (buildingsResult.error) throw buildingsResult.error
    if (roadsResult.error) throw roadsResult.error
    if (decorationsResult.error) throw decorationsResult.error

    console.log('[clearPlayerData] Supabase data cleared')
  } catch (error) {
    console.error('[clearPlayerData] Error clearing Supabase data:', error)
    throw error
  }
}

/**
 * Clear all player data and cache
 * @param includeSupabase - If true, also clears buildings/roads/decorations from Supabase
 */
export async function clearAllPlayerData(includeSupabase: boolean = false): Promise<void> {
  try {
    // Clear IndexedDB
    await clearIndexedDB()
    
    // Clear localStorage
    clearLocalStorage()
    
    // Optionally clear Supabase data
    if (includeSupabase) {
      await clearSupabaseData()
    }
    
    console.log('[clearPlayerData] All player data cleared')
  } catch (error) {
    console.error('[clearPlayerData] Error clearing player data:', error)
    throw error
  }
}

