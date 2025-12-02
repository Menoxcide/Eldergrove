'use client';

import { useEffect } from 'react';
import { useAchievementStore, type PlayerAchievement } from '@/stores/useAchievementStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';

interface AchievementCardProps {
  playerAchievement: PlayerAchievement;
  onClaim: (achievementId: number) => void;
}

const AchievementCard: React.FC<AchievementCardProps> = ({ playerAchievement, onClaim }) => {
  const achievement = playerAchievement.achievement;
  if (!achievement) return null;

  const progress = playerAchievement.progress;
  const target = achievement.condition_value;
  const percentage = Math.min((progress / target) * 100, 100);
  const isCompleted = playerAchievement.completed;
  const isClaimed = playerAchievement.claimed;

  const getCategoryColor = (category: string): string => {
    switch (category) {
      case 'farming': return 'from-green-600 to-emerald-600';
      case 'factory': return 'from-blue-600 to-indigo-600';
      case 'city': return 'from-purple-600 to-pink-600';
      case 'social': return 'from-yellow-600 to-orange-600';
      case 'general': return 'from-gray-600 to-slate-600';
      default: return 'from-gray-600 to-gray-700';
    }
  };

  return (
    <div className={`bg-gradient-to-br ${getCategoryColor(achievement.category)} rounded-2xl p-6 border-2 ${
      isCompleted ? 'border-yellow-400' : 'border-white/20'
    } shadow-lg`}>
      <div className="flex items-start gap-4 mb-4">
        <span className="text-5xl">{achievement.icon}</span>
        <div className="flex-1">
          <h3 className="text-xl font-bold text-white mb-1">{achievement.name}</h3>
          <p className="text-white/90 text-sm mb-2">{achievement.description}</p>
          <div className="flex items-center gap-2 text-xs text-white/80">
            <span className="px-2 py-1 bg-white/20 rounded capitalize">{achievement.category}</span>
            {achievement.reward_title && (
              <span className="px-2 py-1 bg-yellow-500/30 rounded">Title: {achievement.reward_title}</span>
            )}
          </div>
        </div>
      </div>

      <div className="mb-4">
        <div className="flex justify-between text-sm text-white/90 mb-1">
          <span>Progress</span>
          <span className="font-semibold">{progress} / {target}</span>
        </div>
        <div className="w-full bg-white/20 rounded-full h-3 overflow-hidden">
          <div
            className={`h-full transition-all duration-300 ${
              isCompleted ? 'bg-yellow-400' : 'bg-white/60'
            }`}
            style={{ width: `${percentage}%` }}
          />
        </div>
      </div>

      <div className="flex items-center justify-between">
        <div className="flex gap-2 text-sm">
          {achievement.reward_crystals > 0 && (
            <span className="text-yellow-400">💎 {achievement.reward_crystals}</span>
          )}
          {achievement.reward_xp > 0 && (
            <span className="text-blue-400">⭐ {achievement.reward_xp}</span>
          )}
        </div>
        {isCompleted && !isClaimed && (
          <button
            onClick={() => onClaim(achievement.id)}
            className="px-4 py-2 bg-yellow-500 hover:bg-yellow-400 text-gray-900 rounded-lg font-semibold transition-colors"
          >
            Claim Reward
          </button>
        )}
        {isClaimed && (
          <span className="px-4 py-2 bg-green-600 text-white rounded-lg font-semibold">
            Claimed ✓
          </span>
        )}
      </div>
    </div>
  );
};

export default function AchievementsPage() {
  const {
    achievements,
    playerAchievements,
    loading,
    fetchAchievements,
    fetchPlayerAchievements,
    claimAchievement,
    subscribeToAchievements
  } = useAchievementStore();

  useEffect(() => {
    fetchAchievements();
    fetchPlayerAchievements();
    const unsubscribe = subscribeToAchievements();
    return unsubscribe;
  }, [fetchAchievements, fetchPlayerAchievements, subscribeToAchievements]);

  const handleClaim = async (achievementId: number) => {
    try {
      await claimAchievement(achievementId);
    } catch (error) {
      // Error handled in store
    }
  };

  const getAchievementsByCategory = (category: string) => {
    return achievements
      .map(achievement => {
        const playerAchievement = playerAchievements.find(pa => pa.achievement_id === achievement.id);
        return {
          ...achievement,
          playerAchievement: playerAchievement || {
            player_id: '',
            achievement_id: achievement.id,
            progress: 0,
            completed: false,
            completed_at: null,
            claimed: false,
            claimed_at: null,
            achievement
          }
        };
      })
      .filter(item => item.category === category);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Achievements</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  const categories = ['farming', 'factory', 'city', 'social', 'general'];
  const completedCount = playerAchievements.filter(pa => pa.completed).length;
  const totalCount = achievements.length;

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-indigo-900 to-blue-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="mb-6">
          <h1 className="text-3xl font-bold text-white mb-2">Achievements</h1>
          <p className="text-slate-300">
            Completed: {completedCount} / {totalCount} ({Math.round((completedCount / totalCount) * 100)}%)
          </p>
        </div>

        {categories.map((category) => {
          const categoryAchievements = getAchievementsByCategory(category);
          if (categoryAchievements.length === 0) return null;

          return (
            <div key={category} className="mb-8">
              <h2 className="text-2xl font-bold text-white mb-4 capitalize">{category} Achievements</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {categoryAchievements.map((item) => (
                  <AchievementCard
                    key={item.id}
                    playerAchievement={item.playerAchievement as PlayerAchievement}
                    onClaim={handleClaim}
                  />
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

