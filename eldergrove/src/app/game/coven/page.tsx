'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCovenStore } from '@/stores/useCovenStore';
import { useCovenTasksStore } from '@/stores/useCovenTasksStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { useErrorHandler } from '@/hooks/useErrorHandler';

export default function CovenPage() {
  const router = useRouter();
  const { id: playerId } = usePlayerStore();
  const {
    currentCoven,
    availableCovens,
    loading,
    error,
    fetchCoven,
    createCoven,
    joinCoven,
    leaveCoven,
    kickMember,
    updateMemberRole,
    searchCovens,
    refreshCovens,
    subscribeToCovenUpdates,
  } = useCovenStore();
  const {
    tasks,
    taskProgress,
    loading: tasksLoading,
    fetchTasks,
    createTask,
    contributeToTask,
    claimRewards,
    subscribeToTasks
  } = useCovenTasksStore();

  const [showCreateForm, setShowCreateForm] = useState(false);
  const [showBrowse, setShowBrowse] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [covenName, setCovenName] = useState('');
  const [covenEmblem, setCovenEmblem] = useState('🌟');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { showError } = useErrorHandler();

  const emblems = ['🌟', '⚡', '🔥', '💎', '🌙', '☀️', '🌊', '🌿', '⚔️', '🛡️', '🎭', '🔮'];

  useEffect(() => {
    fetchCoven();
    const unsubscribe = subscribeToCovenUpdates();
    return () => {
      unsubscribe();
    };
  }, [fetchCoven, subscribeToCovenUpdates]);

  useEffect(() => {
    if (currentCoven?.id) {
      fetchTasks(currentCoven.id);
      const unsubscribe = subscribeToTasks(currentCoven.id);
      return () => {
        unsubscribe();
      };
    }
  }, [currentCoven?.id, fetchTasks, subscribeToTasks]);

  useEffect(() => {
    if (showBrowse) {
      if (searchQuery.trim()) {
        searchCovens(searchQuery);
      } else {
        refreshCovens();
      }
    }
  }, [searchQuery, showBrowse, searchCovens, refreshCovens]);

  const handleCreateCoven = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!covenName.trim()) {
      showError('Coven Name Required', 'Please enter a name for your coven.');
      return;
    }
    setIsSubmitting(true);
    try {
      await createCoven(covenName.trim(), covenEmblem);
      setShowCreateForm(false);
      setCovenName('');
      setCovenEmblem('🌟');
    } catch (err) {
      // Error already handled in store
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleJoinCoven = async (covenId: string) => {
    setIsSubmitting(true);
    try {
      await joinCoven(covenId);
      setShowBrowse(false);
      setSearchQuery('');
    } catch (err) {
      // Error already handled in store
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleLeaveCoven = async () => {
    if (!confirm('Are you sure you want to leave this coven?')) {
      return;
    }
    setIsSubmitting(true);
    try {
      await leaveCoven();
    } catch (err) {
      // Error already handled in store
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleKickMember = async (memberId: string, memberName: string) => {
    if (!confirm(`Are you sure you want to kick ${memberName || 'this member'}?`)) {
      return;
    }
    setIsSubmitting(true);
    try {
      await kickMember(memberId);
    } catch (err) {
      // Error already handled in store
    } finally {
      setIsSubmitting(false);
    }
  };

  const handlePromoteMember = async (memberId: string, currentRole: string) => {
    const newRole = currentRole === 'member' ? 'elder' : 'leader';
    if (newRole === 'leader' && !confirm('Are you sure you want to transfer leadership? You will become an elder.')) {
      return;
    }
    setIsSubmitting(true);
    try {
      await updateMemberRole(memberId, newRole as 'member' | 'elder' | 'leader');
    } catch (err) {
      // Error already handled in store
    } finally {
      setIsSubmitting(false);
    }
  };

  const isLeader = currentCoven?.leader_id === playerId;
  const currentMember = currentCoven?.members?.find(m => m.player_id === playerId);
  const isElder = currentMember?.role === 'elder' || isLeader;

  if (loading && !currentCoven) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-violet-900 to-fuchsia-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Coven</h1>
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8">
            <Skeleton className="h-32 w-full mb-4" />
            <Skeleton className="h-24 w-full" />
          </div>
        </div>
      </div>
    );
  }

  // Player is in a coven - show coven details
  if (currentCoven) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-violet-900 to-fuchsia-900 p-4 pb-24">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Coven</h1>

          {/* Coven Info Card */}
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-4">
                <span className="text-5xl">{currentCoven.emblem || '🌟'}</span>
                <div>
                  <h2 className="text-2xl font-bold text-white">{currentCoven.name}</h2>
                  <p className="text-slate-300 text-sm">
                    Created {new Date(currentCoven.created_at).toLocaleDateString()}
                  </p>
                </div>
              </div>
              {isLeader && (
                <span className="px-3 py-1 bg-amber-600/30 text-amber-300 rounded-full text-sm font-semibold">
                  ⭐ Leader
                </span>
              )}
            </div>
          </div>

          {/* Members List */}
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
            <h3 className="text-xl font-bold text-white mb-4">
              Members ({currentCoven.members.length})
            </h3>
            {currentCoven.members.length === 0 ? (
              <p className="text-slate-300 text-center py-4">No members yet</p>
            ) : (
              <div className="space-y-3">
                {currentCoven.members.map((member) => {
                  const isCurrentUser = member.player_id === playerId;
                  const canManage = isLeader && !isCurrentUser;

                  return (
                    <div
                      key={member.player_id}
                      className={`flex items-center justify-between p-4 rounded-lg ${
                        isCurrentUser
                          ? 'bg-purple-600/30 border border-purple-500/50'
                          : 'bg-white/5 border border-white/10'
                      }`}
                    >
                      <div className="flex items-center gap-4 flex-1">
                        <div className="w-12 h-12 bg-gradient-to-br from-purple-500 to-indigo-600 rounded-full flex items-center justify-center text-xl font-bold text-white">
                          {member.username?.charAt(0).toUpperCase() || '?'}
                        </div>
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <p className="font-semibold text-white">
                              {member.username || 'Unknown'}
                              {isCurrentUser && ' (You)'}
                            </p>
                            <span
                              className={`px-2 py-0.5 rounded text-xs font-semibold ${
                                member.role === 'leader'
                                  ? 'bg-amber-600/30 text-amber-300'
                                  : member.role === 'elder'
                                  ? 'bg-blue-600/30 text-blue-300'
                                  : 'bg-slate-600/30 text-slate-300'
                              }`}
                            >
                              {member.role.charAt(0).toUpperCase() + member.role.slice(1)}
                            </span>
                          </div>
                          <p className="text-sm text-slate-400">
                            Contribution: {member.contribution.toLocaleString()} • Joined{' '}
                            {new Date(member.joined_at).toLocaleDateString()}
                          </p>
                        </div>
                      </div>
                      {canManage && (
                        <div className="flex gap-2">
                          {member.role !== 'leader' && (
                            <>
                              {member.role === 'member' && (
                                <button
                                  onClick={() => handlePromoteMember(member.player_id, member.role)}
                                  disabled={isSubmitting}
                                  className="px-3 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm transition-colors disabled:opacity-50"
                                  title="Promote to Elder"
                                >
                                  ⬆️
                                </button>
                              )}
                              <button
                                onClick={() => handleKickMember(member.player_id, member.username || '')}
                                disabled={isSubmitting}
                                className="px-3 py-1 bg-red-600 hover:bg-red-700 text-white rounded text-sm transition-colors disabled:opacity-50"
                                title="Kick Member"
                              >
                                🚪
                              </button>
                            </>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Coven Tasks */}
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-2xl font-bold text-white">Coven Tasks</h2>
              {(isLeader || isElder) && (
                <button
                  onClick={() => {
                    // Show create task modal
                    const name = prompt('Task name:');
                    if (name) {
                      const desc = prompt('Task description:');
                      if (desc) {
                        const objectives = [
                          { type: 'produce', target: 100, item: 'bread', description: 'Produce 100 bread' }
                        ];
                        const rewards = { shared_crystals: 500 };
                        createTask(currentCoven.id, name, desc, objectives, rewards).catch(console.error);
                      }
                    }
                  }}
                  className="px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
                >
                  + Create Task
                </button>
              )}
            </div>
            
            {tasksLoading ? (
              <Skeleton className="h-32 w-full" />
            ) : tasks.length === 0 ? (
              <p className="text-slate-300 text-center py-4">No active tasks</p>
            ) : (
              <div className="space-y-4">
                {tasks.map((task) => {
                  const progress = taskProgress[task.id] || [];
                  const totalProgress: Record<string, number> = {};
                  
                  // Calculate total progress across all members
                  progress.forEach(p => {
                    p.contribution.forEach((obj: any) => {
                      if (!totalProgress[obj.type]) {
                        totalProgress[obj.type] = 0;
                      }
                      totalProgress[obj.type] += obj.current || 0;
                    });
                  });

                  const formatTimeLeft = (expiresAt: string | null): string => {
                    if (!expiresAt) return '';
                    const now = Date.now();
                    const expires = new Date(expiresAt).getTime();
                    const diff = expires - now;
                    if (diff <= 0) return 'Expired';
                    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
                    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
                    return `${days}d ${hours}h`;
                  };

                  return (
                    <div
                      key={task.id}
                      className={`bg-gradient-to-br ${
                        task.completed ? 'from-green-900 to-emerald-900' : 'from-purple-900 to-indigo-900'
                      } rounded-xl p-4 border ${task.completed ? 'border-green-500/30' : 'border-purple-500/30'}`}
                    >
                      <div className="flex items-start justify-between mb-3">
                        <div className="flex-1">
                          <h3 className="text-xl font-bold text-white mb-1">{task.name}</h3>
                          <p className="text-slate-300 text-sm mb-2">{task.description}</p>
                          {task.expires_at && (
                            <p className="text-yellow-300 text-xs">⏰ {formatTimeLeft(task.expires_at)}</p>
                          )}
                        </div>
                        {task.completed && (
                          <span className="px-3 py-1 bg-green-600 text-white rounded-lg text-sm font-semibold">
                            Completed ✓
                          </span>
                        )}
                      </div>

                      <div className="space-y-2 mb-3">
                        {task.objectives.map((objective, idx) => {
                          const current = totalProgress[objective.type] || 0;
                          const target = objective.target;
                          const percentage = Math.min((current / target) * 100, 100);
                          
                          return (
                            <div key={idx}>
                              <div className="flex justify-between text-sm text-white/90 mb-1">
                                <span>{objective.description || `${objective.type}: ${objective.item || ''}`}</span>
                                <span className="font-semibold">{current} / {target}</span>
                              </div>
                              <div className="w-full bg-white/20 rounded-full h-2 overflow-hidden">
                                <div
                                  className={`h-full transition-all duration-300 ${
                                    current >= target ? 'bg-green-400' : 'bg-white/60'
                                  }`}
                                  style={{ width: `${percentage}%` }}
                                />
                              </div>
                            </div>
                          );
                        })}
                      </div>

                      <div className="flex items-center justify-between">
                        <div className="text-sm">
                          {task.rewards.shared_crystals && (
                            <span className="text-yellow-400">💎 {task.rewards.shared_crystals} shared crystals</span>
                          )}
                        </div>
                        {task.completed && (isLeader || isElder) && (
                          <button
                            onClick={() => claimRewards(task.id)}
                            className="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-semibold text-sm transition-colors"
                          >
                            Claim Rewards
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
            {!isLeader && (
              <button
                onClick={handleLeaveCoven}
                disabled={isSubmitting}
                className="w-full py-3 px-4 bg-red-600 hover:bg-red-700 text-white rounded-lg font-semibold transition-all disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSubmitting ? 'Leaving...' : 'Leave Coven'}
              </button>
            )}
            {isLeader && (
              <p className="text-center text-slate-300 text-sm">
                As the leader, you cannot leave the coven. Transfer leadership first or disband the coven.
              </p>
            )}
          </div>
        </div>
      </div>
    );
  }

  // Player is not in a coven - show create/join options
  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-violet-900 to-fuchsia-900 p-4 pb-24">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Coven</h1>

        {error && (
          <div className="bg-red-600/20 border border-red-500/50 rounded-lg p-4 mb-6 text-red-200">
            {error}
          </div>
        )}

        {/* Create Coven Form */}
        {showCreateForm ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20">
            <h2 className="text-2xl font-bold text-white mb-4">Create New Coven</h2>
            <form onSubmit={handleCreateCoven} className="space-y-4">
              <div>
                <label className="block text-white mb-2 font-semibold">Coven Name</label>
                <input
                  type="text"
                  value={covenName}
                  onChange={(e) => setCovenName(e.target.value)}
                  placeholder="Enter coven name..."
                  className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  maxLength={50}
                  required
                />
              </div>
              <div>
                <label className="block text-white mb-2 font-semibold">Emblem</label>
                <div className="grid grid-cols-6 gap-2">
                  {emblems.map((emblem) => (
                    <button
                      key={emblem}
                      type="button"
                      onClick={() => setCovenEmblem(emblem)}
                      className={`p-4 text-3xl rounded-lg border-2 transition-all ${
                        covenEmblem === emblem
                          ? 'border-purple-500 bg-purple-500/30 scale-110'
                          : 'border-white/20 bg-white/5 hover:bg-white/10'
                      }`}
                    >
                      {emblem}
                    </button>
                  ))}
                </div>
              </div>
              <div className="flex gap-3">
                <button
                  type="submit"
                  disabled={isSubmitting || !covenName.trim()}
                  className="flex-1 py-3 px-4 bg-purple-600 hover:bg-purple-700 text-white rounded-lg font-semibold transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {isSubmitting ? 'Creating...' : 'Create Coven'}
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowCreateForm(false);
                    setCovenName('');
                    setCovenEmblem('🌟');
                  }}
                  className="px-6 py-3 bg-slate-600 hover:bg-slate-700 text-white rounded-lg font-semibold transition-all"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        ) : (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 mb-6 border border-white/20 text-center">
            <p className="text-slate-300 mb-4">You are not in a coven yet</p>
            <div className="flex gap-4 justify-center">
              <button
                onClick={() => setShowCreateForm(true)}
                className="px-6 py-3 bg-purple-600 hover:bg-purple-700 text-white rounded-lg font-semibold transition-all"
              >
                Create Coven
              </button>
              <button
                onClick={() => {
                  setShowBrowse(true);
                  refreshCovens();
                }}
                className="px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg font-semibold transition-all"
              >
                Browse Covens
              </button>
            </div>
          </div>
        )}

        {/* Browse Covens */}
        {showBrowse && (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-2xl font-bold text-white">Browse Covens</h2>
              <button
                onClick={() => {
                  setShowBrowse(false);
                  setSearchQuery('');
                }}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-700 text-white rounded-lg text-sm transition-all"
              >
                Close
              </button>
            </div>
            <div className="mb-4">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search covens by name..."
                className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-purple-500"
              />
            </div>
            {loading ? (
              <div className="space-y-3">
                <Skeleton className="h-20 w-full" />
                <Skeleton className="h-20 w-full" />
                <Skeleton className="h-20 w-full" />
              </div>
            ) : availableCovens.length === 0 ? (
              <p className="text-slate-300 text-center py-8">
                {searchQuery.trim() ? 'No covens found matching your search' : 'No covens available'}
              </p>
            ) : (
              <div className="space-y-3">
                {availableCovens.map((coven) => (
                  <div
                    key={coven.id}
                    className="flex items-center justify-between p-4 bg-white/5 rounded-lg border border-white/10 hover:bg-white/10 transition-all"
                  >
                    <div className="flex items-center gap-4">
                      <span className="text-3xl">{coven.emblem || '🌟'}</span>
                      <div>
                        <p className="font-semibold text-white">{coven.name}</p>
                        <p className="text-sm text-slate-400">
                          Created {new Date(coven.created_at).toLocaleDateString()}
                        </p>
                      </div>
                    </div>
                    <button
                      onClick={() => handleJoinCoven(coven.id)}
                      disabled={isSubmitting}
                      className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg font-semibold transition-all disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      Join
                    </button>
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
