'use client';

import { useEffect, useState } from 'react';
import { useRegattaStore } from '@/stores/useRegattaStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';

export default function RegattaPage() {
  const {
    currentRegatta,
    participation,
    leaderboard,
    covenLeaderboard,
    loading,
    fetchCurrentRegatta,
    fetchParticipation,
    fetchLeaderboard,
    joinRegatta,
    submitTask,
    claimRewards,
    subscribeToRegatta
  } = useRegattaStore();
  const [leaderboardType, setLeaderboardType] = useState<'global' | 'coven'>('global');

  useEffect(() => {
    fetchCurrentRegatta();
    if (currentRegatta?.id) {
      fetchParticipation(currentRegatta.id);
      fetchLeaderboard(currentRegatta.id, leaderboardType);
      const unsubscribe = subscribeToRegatta(currentRegatta.id);
      return unsubscribe;
    }
  }, [currentRegatta?.id, leaderboardType, fetchCurrentRegatta, fetchParticipation, fetchLeaderboard, subscribeToRegatta]);

  const formatTimeLeft = (endDate: string): string => {
    const now = Date.now();
    const ends = new Date(endDate).getTime();
    const diff = ends - now;
    if (diff <= 0) return 'Ended';
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    return `${days}d ${hours}h`;
  };

  const handleJoin = async () => {
    if (!currentRegatta) return;
    try {
      await joinRegatta(currentRegatta.id);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleSubmitTask = async (taskIndex: number) => {
    if (!currentRegatta) return;
    try {
      await submitTask(currentRegatta.id, taskIndex);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleClaimRewards = async () => {
    if (!currentRegatta) return;
    try {
      await claimRewards(currentRegatta.id);
    } catch (error) {
      // Error handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-yellow-900 via-orange-900 to-red-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Regatta</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  if (!currentRegatta) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-yellow-900 via-orange-900 to-red-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Regatta</h1>
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg">No active regatta</p>
            <p className="text-slate-400 mt-2">Check back later for the next competition!</p>
          </div>
        </div>
      </div>
    );
  }

  const isActive = currentRegatta.status === 'active';
  const isCompleted = currentRegatta.status === 'completed';
  const hasJoined = participation !== null;

  return (
    <div className="min-h-screen bg-gradient-to-br from-yellow-900 via-orange-900 to-red-900 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Regatta</h1>

        {/* Regatta Info */}
        <div className="bg-gradient-to-br from-yellow-800 to-orange-800 rounded-2xl p-6 mb-6 border-2 border-yellow-500/30">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-2xl font-bold text-white mb-1">{currentRegatta.name}</h2>
              <p className="text-yellow-200 text-sm">
                {isActive ? `Ends in: ${formatTimeLeft(currentRegatta.end_date)}` : 
                 isCompleted ? 'Competition Ended' : 
                 `Starts: ${new Date(currentRegatta.start_date).toLocaleDateString()}`}
              </p>
            </div>
            {hasJoined && participation && (
              <div className="text-right">
                <div className="text-yellow-300 text-sm">Your Points</div>
                <div className="text-white text-3xl font-bold">{participation.points}</div>
              </div>
            )}
          </div>

          {!hasJoined && isActive && (
            <button
              onClick={handleJoin}
              className="w-full px-6 py-3 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-lg transition-colors"
            >
              Join Regatta 🏁
            </button>
          )}

          {isCompleted && hasJoined && (
            <button
              onClick={handleClaimRewards}
              className="w-full px-6 py-3 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-semibold text-lg transition-colors"
            >
              Claim Rewards 🏆
            </button>
          )}
        </div>

        {/* Tasks */}
        {hasJoined && (
          <div className="mb-6">
            <h2 className="text-xl font-bold text-white mb-4">Tasks</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {currentRegatta.tasks.map((task, index) => {
                const isCompleted = participation?.tasks_completed.includes(index) || false;
                return (
                  <div
                    key={index}
                    className={`bg-gradient-to-br ${
                      isCompleted ? 'from-green-900 to-emerald-900' : 'from-slate-800 to-slate-900'
                    } rounded-xl p-4 border ${isCompleted ? 'border-green-500/30' : 'border-slate-700'}`}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <h3 className="text-white font-semibold">Task {index + 1}</h3>
                      <span className="text-yellow-400 font-semibold">{task.points} pts</span>
                    </div>
                    <p className="text-slate-300 text-sm mb-3">
                      {task.type === 'produce' && `Produce ${task.target} ${task.item || 'items'}`}
                      {task.type === 'harvest' && `Harvest ${task.target} crops`}
                      {task.type === 'mine' && `Mine ${task.target} ores`}
                      {task.type === 'order' && `Complete ${task.target} skyport orders`}
                    </p>
                    {isCompleted ? (
                      <span className="px-3 py-1 bg-green-600 text-white rounded-lg text-sm font-semibold">
                        Completed ✓
                      </span>
                    ) : (
                      <button
                        onClick={() => handleSubmitTask(index)}
                        className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-semibold text-sm transition-colors"
                      >
                        Submit Task
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Leaderboard */}
        {hasJoined && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-xl font-bold text-white">Leaderboard</h2>
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    setLeaderboardType('global');
                    if (currentRegatta?.id) {
                      fetchLeaderboard(currentRegatta.id, 'global');
                    }
                  }}
                  className={`px-4 py-2 rounded-lg font-semibold text-sm transition-colors ${
                    leaderboardType === 'global'
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-700 text-slate-300'
                  }`}
                >
                  Global
                </button>
                <button
                  onClick={() => {
                    setLeaderboardType('coven');
                    if (currentRegatta?.id) {
                      fetchLeaderboard(currentRegatta.id, 'coven');
                    }
                  }}
                  className={`px-4 py-2 rounded-lg font-semibold text-sm transition-colors ${
                    leaderboardType === 'coven'
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-700 text-slate-300'
                  }`}
                >
                  Coven
                </button>
              </div>
            </div>

            {leaderboardType === 'global' ? (
              <div className="space-y-2">
                {leaderboard.slice(0, 20).map((entry, index) => (
                  <div
                    key={entry.player_id || index}
                    className={`flex items-center justify-between p-4 rounded-lg ${
                      index < 3 ? 'bg-gradient-to-r from-yellow-900 to-orange-900 border-2 border-yellow-500/50' : 'bg-slate-800/60'
                    }`}
                  >
                    <div className="flex items-center gap-4">
                      <span className="text-2xl font-bold text-white w-8">
                        {index === 0 ? '🥇' : index === 1 ? '🥈' : index === 2 ? '🥉' : `#${index + 1}`}
                      </span>
                      <div>
                        <div className="text-white font-semibold">{entry.username || 'Unknown'}</div>
                        {entry.coven_name && (
                          <div className="text-slate-400 text-xs">{entry.coven_name}</div>
                        )}
                      </div>
                    </div>
                    <div className="text-yellow-400 font-bold">{entry.points || 0} pts</div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="space-y-2">
                {covenLeaderboard.slice(0, 10).map((entry, index) => (
                  <div
                    key={entry.coven_id}
                    className={`flex items-center justify-between p-4 rounded-lg ${
                      index < 3 ? 'bg-gradient-to-r from-yellow-900 to-orange-900 border-2 border-yellow-500/50' : 'bg-slate-800/60'
                    }`}
                  >
                    <div className="flex items-center gap-4">
                      <span className="text-2xl font-bold text-white w-8">
                        {index === 0 ? '🥇' : index === 1 ? '🥈' : index === 2 ? '🥉' : `#${index + 1}`}
                      </span>
                      <div>
                        <div className="text-white font-semibold">{entry.coven_name}</div>
                        <div className="text-slate-400 text-xs">{entry.member_count} members</div>
                      </div>
                    </div>
                    <div className="text-yellow-400 font-bold">{entry.total_points} pts</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

