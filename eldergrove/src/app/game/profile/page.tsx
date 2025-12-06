'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useCovenStore } from '@/stores/useCovenStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { useErrorHandler } from '@/hooks/useErrorHandler';

export default function ProfilePage() {
  const router = useRouter();
  const { id, username, crystals, level, xp, aether, loading: playerLoading, fetchPlayerProfile } = usePlayerStore();
  const { currentCoven, fetchCoven, loading: covenLoading } = useCovenStore();
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [isEditingUsername, setIsEditingUsername] = useState(false);
  const [newUsername, setNewUsername] = useState('');
  const [isSavingUsername, setIsSavingUsername] = useState(false);
  const { handleError, showError } = useErrorHandler();

  useEffect(() => {
    fetchCoven();
  }, [fetchCoven]);

  useEffect(() => {
    setNewUsername(username || '');
  }, [username]);

  const handleSaveUsername = async () => {
    if (!newUsername.trim()) {
      showError('Username Required', 'Please enter a username.');
      return;
    }
    if (newUsername.trim().length < 3) {
      showError('Username Too Short', 'Username must be at least 3 characters long.');
      return;
    }
    if (newUsername.trim().length > 20) {
      showError('Username Too Long', 'Username must be 20 characters or less.');
      return;
    }
    if (!/^[a-zA-Z0-9_-]+$/.test(newUsername.trim())) {
      showError('Invalid Username', 'Username can only contain letters, numbers, underscores, and hyphens.');
      return;
    }
    if (newUsername.trim() === username) {
      setIsEditingUsername(false);
      return;
    }

    setIsSavingUsername(true);
    try {
      const supabase = createClient();
      const { error } = await supabase
        .from('profiles')
        .update({ username: newUsername.trim() })
        .eq('id', id);

      if (error) {
        if (error.code === '23505') {
          showError('Username Taken', 'This username is already taken. Please choose another.');
        } else {
          throw error;
        }
        return;
      }

      await fetchPlayerProfile();
      setIsEditingUsername(false);
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', 'Username updated successfully!');
    } catch (err: unknown) {
      handleError(err, 'Failed to update username');
    } finally {
      setIsSavingUsername(false);
    }
  };

  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signOut();
      if (error) {
        handleError(error, error.message);
      } else {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
        useGameMessageStore.getState().addMessage('success', 'Logged out successfully');
        router.push('/login');
      }
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to logout'
      handleError(err, errorMessage);
    } finally {
      setIsLoggingOut(false);
    }
  };

  if (playerLoading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Profile</h1>
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8">
            <Skeleton className="h-32 w-full mb-4" />
            <Skeleton className="h-24 w-full mb-4" />
            <Skeleton className="h-24 w-full" />
          </div>
        </div>
      </div>
    );
  }

  // Calculate XP needed for next level (simple formula: level * 1000)
  const xpForNextLevel = level * 1000;
  const xpProgress = (xp / xpForNextLevel) * 100;

  // Calculate level-based benefits
  const storageBonus = level * 5; // +5 storage per level
  const energyBonus = level * 2; // +2 energy per level
  const productionBonus = Math.min(level, 50) * 1; // 1% per level, max 50%
  const discountPercent = Math.min(level * 0.5, 25); // 0.5% per level, max 25%

  // Next level benefits
  const nextLevel = level + 1;
  const nextStorageBonus = nextLevel * 5;
  const nextEnergyBonus = nextLevel * 2;
  const nextProductionBonus = Math.min(nextLevel, 50) * 1;
  const nextDiscountPercent = Math.min(nextLevel * 0.5, 25);

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4 pb-24">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Profile</h1>
        
        {/* Player Info Card */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
          <div className="flex items-center gap-6 mb-6">
            <div className="w-24 h-24 bg-gradient-to-br from-purple-500 to-indigo-600 rounded-full flex items-center justify-center text-4xl font-bold text-white shadow-lg">
              {username?.charAt(0).toUpperCase() || '?'}
            </div>
            <div className="flex-1">
              <h2 className="text-2xl font-bold text-white mb-2">{username || 'Adventurer'}</h2>
              <div className="flex items-center gap-4 text-sm text-slate-300">
                <span className="flex items-center gap-1">
                  <span className="text-xl">👑</span>
                  Level {level}
                </span>
                <span className="flex items-center gap-1">
                  <span className="text-xl">💎</span>
                  {crystals.toLocaleString()} Crystals
                </span>
                {aether > 0 && (
                  <span className="flex items-center gap-1">
                    <span className="text-xl">✨</span>
                    {aether.toLocaleString()} Aether
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* XP Progress Bar */}
          <div className="mb-4">
            <div className="flex justify-between text-sm text-slate-300 mb-2">
              <span>Experience Points</span>
              <span>{xp.toLocaleString()} / {xpForNextLevel.toLocaleString()} XP</span>
            </div>
            <div className="w-full bg-slate-700/50 rounded-full h-4 overflow-hidden">
              <div
                className="bg-gradient-to-r from-amber-500 to-yellow-400 h-full transition-all duration-500 rounded-full"
                style={{ width: `${Math.min(xpProgress, 100)}%` }}
              />
            </div>
          </div>

          {/* Username Editor */}
          <div className="border-t border-white/20 pt-4">
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-semibold text-white">Username</label>
              {!isEditingUsername && (
                <button
                  onClick={() => setIsEditingUsername(true)}
                  className="text-sm text-purple-400 hover:text-purple-300 transition-colors"
                >
                  {username ? 'Edit' : 'Set Username'}
                </button>
              )}
            </div>
            {isEditingUsername ? (
              <div className="flex gap-2">
                <input
                  type="text"
                  value={newUsername}
                  onChange={(e) => setNewUsername(e.target.value)}
                  placeholder="Enter username..."
                  maxLength={20}
                  className="flex-1 px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      handleSaveUsername();
                    } else if (e.key === 'Escape') {
                      setIsEditingUsername(false);
                      setNewUsername(username || '');
                    }
                  }}
                  autoFocus
                />
                <button
                  onClick={handleSaveUsername}
                  disabled={isSavingUsername}
                  className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg font-semibold transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSavingUsername ? 'Saving...' : 'Save'}
                </button>
                <button
                  onClick={() => {
                    setIsEditingUsername(false);
                    setNewUsername(username || '');
                  }}
                  disabled={isSavingUsername}
                  className="px-4 py-2 bg-slate-600 hover:bg-slate-700 text-white rounded-lg font-semibold transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Cancel
                </button>
              </div>
            ) : (
              <p className="text-slate-300">{username || 'Not set'}</p>
            )}
            {isEditingUsername && (
              <p className="text-xs text-slate-400 mt-2">
                3-20 characters, letters, numbers, underscores, and hyphens only
              </p>
            )}
          </div>
        </div>

        {/* Coven Membership Card */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
          <h3 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
            <span>👥</span>
            Coven Membership
          </h3>
          {covenLoading ? (
            <Skeleton className="h-16 w-full" />
          ) : currentCoven ? (
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-lg font-semibold text-white">{currentCoven.name}</p>
                  <p className="text-sm text-slate-300">
                    {currentCoven.emblem && <span className="mr-2">{currentCoven.emblem}</span>}
                    {currentCoven.members.length} member{currentCoven.members.length !== 1 ? 's' : ''}
                  </p>
                </div>
                <button
                  onClick={() => router.push('/game/coven')}
                  className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors"
                >
                  View Coven
                </button>
              </div>
              {currentCoven.members.find(m => m.player_id === id)?.role === 'leader' && (
                <p className="text-sm text-amber-400 font-semibold">⭐ You are the leader</p>
              )}
            </div>
          ) : (
            <div className="text-center py-4">
              <p className="text-slate-300 mb-4">You are not in a coven yet</p>
              <button
                onClick={() => router.push('/game/coven')}
                className="px-6 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors"
              >
                Join or Create Coven
              </button>
            </div>
          )}
        </div>

        {/* Level Benefits Card */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
          <h3 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
            <span>⭐</span>
            Level Benefits
          </h3>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Storage Bonus</p>
              <p className="text-2xl font-bold text-emerald-400">+{storageBonus}</p>
              <p className="text-xs text-slate-400 mt-1">Next: +{nextStorageBonus}</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Energy Bonus</p>
              <p className="text-2xl font-bold text-blue-400">+{energyBonus}</p>
              <p className="text-xs text-slate-400 mt-1">Next: +{nextEnergyBonus}</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Production Speed</p>
              <p className="text-2xl font-bold text-purple-400">+{productionBonus}%</p>
              <p className="text-xs text-slate-400 mt-1">Next: +{nextProductionBonus}%</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Purchase Discount</p>
              <p className="text-2xl font-bold text-amber-400">{discountPercent.toFixed(1)}%</p>
              <p className="text-xs text-slate-400 mt-1">Next: {nextDiscountPercent.toFixed(1)}%</p>
            </div>
          </div>
          <div className="text-xs text-slate-400 bg-white/5 rounded-lg p-3">
            <p className="font-semibold text-slate-300 mb-1">How Level Benefits Work:</p>
            <ul className="list-disc list-inside space-y-1">
              <li>Storage: +5 capacity per level</li>
              <li>Energy: +2 max energy per level</li>
              <li>Production: +1% speed per level (max 50%)</li>
              <li>Discount: +0.5% per level (max 25%)</li>
            </ul>
          </div>
        </div>

        {/* Stats Card */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
          <h3 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
            <span>📊</span>
            Statistics
          </h3>
          <div className="grid grid-cols-2 gap-4">
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Total Crystals</p>
              <p className="text-2xl font-bold text-white">{crystals.toLocaleString()}</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Current Level</p>
              <p className="text-2xl font-bold text-white">{level}</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Experience</p>
              <p className="text-2xl font-bold text-white">{xp.toLocaleString()}</p>
            </div>
            <div className="bg-white/5 rounded-lg p-4">
              <p className="text-slate-400 text-sm mb-1">Player ID</p>
              <p className="text-xs font-mono text-slate-300 truncate">{id || 'N/A'}</p>
            </div>
          </div>
        </div>

        {/* Settings Card */}
        <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
          <h3 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
            <span>⚙️</span>
            Settings
          </h3>
          <div className="space-y-3">
            <button
              onClick={() => router.push('/game/premium-shop')}
              className="w-full py-3 px-4 bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-500 hover:to-pink-500 text-white rounded-lg font-semibold transition-all active:scale-95 flex items-center justify-center gap-2"
            >
              <span>✨</span>
              Premium Shop
            </button>
            <button
              onClick={() => router.push('/game/settings')}
              className="w-full py-3 px-4 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-all active:scale-95 flex items-center justify-center gap-2"
            >
              <span>⚙️</span>
              Settings
            </button>
            <button
              onClick={handleLogout}
              disabled={isLoggingOut}
              className={`w-full py-3 px-4 rounded-lg font-semibold transition-all ${
                isLoggingOut
                  ? 'bg-gray-600 cursor-not-allowed text-gray-400'
                  : 'bg-red-600 hover:bg-red-700 active:scale-95 text-white'
              }`}
            >
              {isLoggingOut ? 'Logging out...' : 'Logout'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
