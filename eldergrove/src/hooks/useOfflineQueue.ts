import { createClient } from '@/lib/supabase/client'
import { get, set } from 'idb-keyval'
import { handleError } from '@/hooks/useErrorHandler'

const QUEUE_KEY = 'eldergrove-offline-queue'

interface QueuedAction {
  type: string
  data: Record<string, unknown>
  timestamp: number
}

type ActionType =
  | 'plant_crop'
  | 'harvest_plot'
  | 'start_factory_production'
  | 'collect_factory'
  | 'collect_armory'

type ActionDataMap = {
  plant_crop: {
    p_plot_index: number
    p_crop_id: number
  }
  harvest_plot: {
    p_plot_index: number
  }
  start_factory_production: {
    p_factory_type: string
    p_recipe_name: string
  }
  collect_factory: {
    p_slot: number
  }
  collect_armory: {
    p_slot: number
  }
}

function isNetworkError(error: unknown): boolean {
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    return true
  }
  if (error instanceof Error) {
    const msg = error.message.toLowerCase()
    return (
      msg.includes('fetch') ||
      msg.includes('network') ||
      msg.includes('failed to execute') ||
      error.name === 'TypeError' ||
      error.name === 'AbortError'
    )
  }
  return false
}

export function useOfflineQueue() {
  const queueAction = async <K extends ActionType>(
    actionType: K,
    actionData: ActionDataMap[K]
  ): Promise<boolean> => {
    const supabase = createClient()
    try {
      await supabase.rpc(actionType, actionData)
      return true
    } catch (error: unknown) {
      if (isNetworkError(error)) {
        const action: QueuedAction = {
          type: actionType,
          data: actionData,
          timestamp: Date.now(),
        }
        const queue: QueuedAction[] = (await get(QUEUE_KEY)) || []
        await set(QUEUE_KEY, [...queue, action])
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage('info', 'Action queued for later processing')
        return false
      } else {
        handleError(error, 'Non-network RPC error')
        throw error
      }
    }
  }

  return { queueAction }
}