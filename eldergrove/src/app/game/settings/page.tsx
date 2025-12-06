'use client';

import { useEffect, useState } from 'react';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { requestNotificationPermission, subscribeToPushNotifications, registerPushSubscription, updateNotificationPreferences } from '@/lib/pushNotifications';
import { createClient } from '@/lib/supabase/client';
import { useErrorHandler } from '@/hooks/useErrorHandler';

export default function SettingsPage() {
  const { aether, crystals } = usePlayerStore();
  const [notificationsEnabled, setNotificationsEnabled] = useState(false);
  const [preferences, setPreferences] = useState({
    crops_ready: true,
    factory_complete: true,
    orders_expiring: true,
    quest_available: true,
    friend_help: true,
    coven_task_complete: true
  });
  const [loading, setLoading] = useState(false);
  const { handleError, showError } = useErrorHandler();

  useEffect(() => {
    checkNotificationStatus();
    fetchPreferences();
  }, []);

  const checkNotificationStatus = async () => {
    if ('Notification' in window) {
      setNotificationsEnabled(Notification.permission === 'granted');
    }
  };

  const fetchPreferences = async () => {
    try {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;

      const { data, error } = await supabase
        .from('notification_preferences')
        .select('*')
        .eq('player_id', user.id)
        .single();

      if (data && !error) {
        setPreferences({
          crops_ready: data.crops_ready ?? true,
          factory_complete: data.factory_complete ?? true,
          orders_expiring: data.orders_expiring ?? true,
          quest_available: data.quest_available ?? true,
          friend_help: data.friend_help ?? true,
          coven_task_complete: data.coven_task_complete ?? true
        });
      }
    } catch (error) {
      console.error('Error fetching preferences:', error);
    }
  };

  const handleEnableNotifications = async () => {
    setLoading(true);
    try {
      const hasPermission = await requestNotificationPermission();
      if (!hasPermission) {
        showError('Permission Denied', 'Notification permission was denied. Please enable notifications in your browser settings.');
        setLoading(false);
        return;
      }

      const subscription = await subscribeToPushNotifications();
      if (subscription) {
        await registerPushSubscription(subscription, {
          userAgent: navigator.userAgent,
          platform: navigator.platform
        });
        setNotificationsEnabled(true);
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
        useGameMessageStore.getState().addMessage('success', 'Notifications enabled!');
      } else {
        showError('Subscription Failed', 'Failed to subscribe to push notifications. Please try again.');
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to subscribe to notifications'
      handleError(error, errorMessage);
    } finally {
      setLoading(false);
    }
  };

  const handlePreferenceChange = async (key: keyof typeof preferences, value: boolean) => {
    const newPreferences = { ...preferences, [key]: value };
    setPreferences(newPreferences);
    
    try {
      await updateNotificationPreferences({ [key]: value });
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', 'Preferences updated');
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to update preferences'
      handleError(error, errorMessage);
      // Revert on error
      setPreferences(preferences);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-indigo-900 p-4">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Settings</h1>

        {/* Currency Display */}
        <div className="flex items-center justify-center gap-4 mb-8">
          <div className="flex items-center gap-2 px-4 py-2 bg-purple-800/60 rounded-lg border border-purple-500/30">
            <span className="text-2xl">✨</span>
            <span className="text-white font-mono">{aether.toLocaleString()}</span>
            <span className="text-purple-300 text-sm">Aether</span>
          </div>
          <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
            <span className="text-xl">💎</span>
            <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            <span className="text-slate-300 text-sm">Crystals</span>
          </div>
        </div>

        {/* Notifications Section */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
          <h2 className="text-2xl font-bold text-white mb-4">Push Notifications</h2>
          
          {!notificationsEnabled ? (
            <div className="mb-4">
              <p className="text-slate-300 mb-4">
                Enable push notifications to get notified when crops are ready, factories complete, and more!
              </p>
              <button
                onClick={handleEnableNotifications}
                disabled={loading}
                className="px-6 py-3 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors disabled:opacity-50"
              >
                {loading ? 'Enabling...' : 'Enable Notifications'}
              </button>
            </div>
          ) : (
            <div className="mb-4">
              <div className="flex items-center gap-2 mb-4">
                <span className="text-green-400 text-xl">✓</span>
                <span className="text-green-400 font-semibold">Notifications Enabled</span>
              </div>
              <p className="text-slate-300 text-sm mb-4">Customize which notifications you receive:</p>
              
              <div className="space-y-3">
                {Object.entries(preferences).map(([key, value]) => (
                  <label key={key} className="flex items-center justify-between p-3 bg-slate-800/60 rounded-lg cursor-pointer hover:bg-slate-700/60 transition-colors">
                    <span className="text-white capitalize">
                      {key.replace('_', ' ')}
                    </span>
                    <input
                      type="checkbox"
                      checked={value}
                      onChange={(e) => handlePreferenceChange(key as keyof typeof preferences, e.target.checked)}
                      className="w-5 h-5 rounded accent-green-600"
                    />
                  </label>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Game Info */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
          <h2 className="text-2xl font-bold text-white mb-4">About Eldergrove</h2>
          <p className="text-slate-300 mb-2">
            Build your magical town, grow crops, craft items, and explore the world of Eldergrove!
          </p>
          <p className="text-slate-400 text-sm">
            Version 1.0.0 • Built with Next.js & Supabase
          </p>
        </div>
      </div>
    </div>
  );
}

