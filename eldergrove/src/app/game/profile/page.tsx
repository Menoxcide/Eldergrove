'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useCovenStore } from '@/stores/useCovenStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import toast from 'react-hot-toast';

export default function ProfilePage() {
  const router = useRouter();
  const { id, username, crystals, level, xp, aether, loading: playerLoading } = usePlayerStore();
  const { currentCoven, fetchCoven, loading: covenLoading } = useCovenStore();
  const [isLoggingOut, setIsLoggingOut] = useState(false);

  useEffect(() => {
    fetchCoven();
  }, [fetchCoven]);

  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      const supabase = createClient();
      const { error } = await supabase.auth.signOut();
      if (error) {
        toast.error(`Failed to logout: ${error.message}`);
      } else {
        toast.success('Logged out successfully');
        router.push('/login');
      }
    } catch (err: any) {
      toast.error(`Failed to logout: ${err.message}`);
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
