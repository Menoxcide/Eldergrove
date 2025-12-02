// Push notifications service using Web Push API

export interface PushSubscriptionData {
  endpoint: string
  keys: {
    p256dh: string
    auth: string
  }
}

export async function requestNotificationPermission(): Promise<boolean> {
  if (!('Notification' in window)) {
    console.warn('This browser does not support notifications')
    return false
  }

  if (Notification.permission === 'granted') {
    return true
  }

  if (Notification.permission !== 'denied') {
    const permission = await Notification.requestPermission()
    return permission === 'granted'
  }

  return false
}

export async function subscribeToPushNotifications(): Promise<PushSubscriptionData | null> {
  if (!('serviceWorker' in navigator)) {
    console.warn('Service workers are not supported')
    return null
  }

  try {
    // Register service worker
    const registration = await navigator.serviceWorker.register('/sw.js')
    await navigator.serviceWorker.ready

    // Subscribe to push notifications
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(
        process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY || ''
      ) as BufferSource
    })

    const subscriptionData: PushSubscriptionData = {
      endpoint: subscription.endpoint,
      keys: {
        p256dh: arrayBufferToBase64(subscription.getKey('p256dh')!),
        auth: arrayBufferToBase64(subscription.getKey('auth')!)
      }
    }

    return subscriptionData
  } catch (error) {
    console.error('Error subscribing to push notifications:', error)
    return null
  }
}

export async function registerPushSubscription(
  subscriptionData: PushSubscriptionData,
  deviceInfo?: Record<string, any>
): Promise<void> {
  const { createClient } = await import('./supabase/client')
  const supabase = createClient()

  const { error } = await supabase.rpc('register_push_subscription', {
    p_endpoint: subscriptionData.endpoint,
    p_p256dh: subscriptionData.keys.p256dh,
    p_auth: subscriptionData.keys.auth,
    p_device_info: deviceInfo || null
  })

  if (error) {
    throw error
  }
}

export async function updateNotificationPreferences(preferences: {
  crops_ready?: boolean
  factory_complete?: boolean
  orders_expiring?: boolean
  quest_available?: boolean
  friend_help?: boolean
  coven_task_complete?: boolean
}): Promise<void> {
  const { createClient } = await import('./supabase/client')
  const supabase = createClient()

  const { error } = await supabase.rpc('update_notification_preferences', {
    p_crops_ready: preferences.crops_ready ?? null,
    p_factory_complete: preferences.factory_complete ?? null,
    p_orders_expiring: preferences.orders_expiring ?? null,
    p_quest_available: preferences.quest_available ?? null,
    p_friend_help: preferences.friend_help ?? null,
    p_coven_task_complete: preferences.coven_task_complete ?? null
  })

  if (error) {
    throw error
  }
}

// Helper functions
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')

  const rawData = window.atob(base64)
  const outputArray = new Uint8Array(rawData.length)

  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer)
  let binary = ''
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return window.btoa(binary)
}

