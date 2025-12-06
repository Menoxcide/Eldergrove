'use client';

import { useEffect } from 'react';
import { useQuestStore, type QuestProgress } from '@/stores/useQuestStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';

interface QuestCardProps {
  questProgress: QuestProgress;
  onStart?: (questId: number) => void;
  onClaim: (questId: number) => void;
}

const QuestCard: React.FC<QuestCardProps> = ({ questProgress, onStart, onClaim }) => {
  const quest = questProgress.quest;
  if (!quest) return null;

  const getQuestTypeColor = (type: string): string => {
    switch (type) {
      case 'tutorial': return 'from-blue-600 to-cyan-600';
      case 'daily': return 'from-yellow-600 to-orange-600';
      case 'weekly': return 'from-purple-600 to-pink-600';
      case 'story': return 'from-green-600 to-emerald-600';
      default: return 'from-gray-600 to-gray-700';
    }
  };

  const getQuestTypeIcon = (type: string): string => {
    switch (type) {
      case 'tutorial': return '📚';
      case 'daily': return '📅';
      case 'weekly': return '📆';
      case 'story': return '📖';
      default: return '📋';
    }
  };

  const formatTimeLeft = (expiresAt: string | null): string => {
    if (!expiresAt) return '';
    const now = Date.now();
    const expires = new Date(expiresAt).getTime();
    const diff = expires - now;
    if (diff <= 0) return 'Expired';
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    return `${hours}h ${minutes}m`;
  };

  return (
    <div className={`bg-gradient-to-br ${getQuestTypeColor(quest.type)} rounded-2xl p-6 border-2 ${
      questProgress.completed ? 'border-yellow-400' : 'border-white/20'
    } shadow-lg`}>
      <div className="flex items-start gap-3 mb-4">
        <span className="text-4xl">{getQuestTypeIcon(quest.type)}</span>
        <div className="flex-1">
          <div className="flex items-center justify-between mb-1">
            <h3 className="text-xl font-bold text-white">{quest.title}</h3>
            <span className="text-xs text-white/80 px-2 py-1 bg-white/20 rounded capitalize">{quest.type}</span>
          </div>
          <p className="text-white/90 text-sm mb-2">{quest.description}</p>
          {questProgress.expires_at && (
            <p className="text-yellow-300 text-xs">⏰ {formatTimeLeft(questProgress.expires_at)}</p>
          )}
        </div>
      </div>

      <div className="mb-4 space-y-2">
        {questProgress.progress.map((objective, index) => {
          const current = objective.current || 0;
          const target = objective.target;
          const percentage = Math.min((current / target) * 100, 100);
          
          return (
            <div key={index}>
              <div className="flex justify-between text-sm text-white/90 mb-1">
                <span>{objective.description}</span>
                <span className="font-semibold">{current} / {target}</span>
              </div>
              <div className="w-full bg-white/20 rounded-full h-2 overflow-hidden">
                <div
                  className={`h-full transition-all duration-300 ${
                    current >= target ? 'bg-yellow-400' : 'bg-white/60'
                  }`}
                  style={{ width: `${percentage}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>

      <div className="flex items-center justify-between">
        <div className="flex gap-2 text-sm">
          {quest.rewards.crystals && (
            <span className="text-yellow-400">💎 {quest.rewards.crystals}</span>
          )}
          {quest.rewards.xp && (
            <span className="text-blue-400">⭐ {quest.rewards.xp}</span>
          )}
        </div>
        {!questProgress.started_at && onStart && (
          <button
            onClick={() => onStart(quest.id)}
            className="px-4 py-2 bg-white hover:bg-gray-100 text-gray-900 rounded-lg font-semibold transition-colors"
          >
            Start Quest
          </button>
        )}
        {questProgress.completed && !questProgress.claimed && (
          <button
            onClick={() => onClaim(quest.id)}
            className="px-4 py-2 bg-yellow-500 hover:bg-yellow-400 text-gray-900 rounded-lg font-semibold transition-colors"
          >
            Claim Reward
          </button>
        )}
        {questProgress.claimed && (
          <span className="px-4 py-2 bg-green-600 text-white rounded-lg font-semibold">
            Claimed ✓
          </span>
        )}
      </div>
    </div>
  );
};

export default function QuestsPage() {
  const {
    quests,
    playerQuests,
    loading,
    fetchQuests,
    fetchPlayerQuests,
    startQuest,
    claimQuestReward,
    generateDailyQuests,
    subscribeToQuests
  } = useQuestStore();

  useEffect(() => {
    fetchQuests();
    fetchPlayerQuests();
    generateDailyQuests(); // Generate daily quests on page load
    const unsubscribe = subscribeToQuests();
    return unsubscribe;
  }, [fetchQuests, fetchPlayerQuests, generateDailyQuests, subscribeToQuests]);

  const handleStart = async (questId: number) => {
    try {
      await startQuest(questId);
    } catch {
      // Error handled in store
    }
  };

  const handleClaim = async (questId: number) => {
    try {
      await claimQuestReward(questId);
    } catch {
      // Error handled in store
    }
  };

  const getQuestsByType = (type: string) => {
    if (type === 'tutorial' || type === 'story') {
      // Show all available quests
      return quests
        .filter(q => q.type === type)
        .map(quest => {
          const progress = playerQuests.find(pq => pq.quest_id === quest.id);
          return {
            quest,
            progress: progress || {
              player_id: '',
              quest_id: quest.id,
              progress: quest.objectives.map(obj => ({ ...obj, current: 0 })),
              completed: false,
              completed_at: null,
              claimed: false,
              claimed_at: null,
              started_at: '',
              expires_at: null,
              quest
            }
          };
        });
    } else {
      // Show only started quests for daily/weekly
      return playerQuests
        .filter(pq => pq.quest?.type === type)
        .map(pq => ({ quest: pq.quest!, progress: pq }));
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Quests</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  const tutorialQuests = getQuestsByType('tutorial');
  const dailyQuests = getQuestsByType('daily');
  const weeklyQuests = getQuestsByType('weekly');
  const storyQuests = getQuestsByType('story');

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-900 via-purple-900 to-pink-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="mb-6 flex justify-between items-center">
          <h1 className="text-3xl font-bold text-white">Quests</h1>
          <button
            onClick={generateDailyQuests}
            className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
          >
            Refresh Daily Quests
          </button>
        </div>

        {tutorialQuests.length > 0 && (
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-white mb-4">Tutorial Quests</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {tutorialQuests.map((item) => (
                <QuestCard
                  key={item.quest.id}
                  questProgress={item.progress}
                  onStart={handleStart}
                  onClaim={handleClaim}
                />
              ))}
            </div>
          </div>
        )}

        {dailyQuests.length > 0 && (
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-white mb-4">Daily Quests</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {dailyQuests.map((item) => (
                <QuestCard
                  key={item.progress.quest_id}
                  questProgress={item.progress}
                  onClaim={handleClaim}
                />
              ))}
            </div>
          </div>
        )}

        {weeklyQuests.length > 0 && (
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-white mb-4">Weekly Quests</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {weeklyQuests.map((item) => (
                <QuestCard
                  key={item.progress.quest_id}
                  questProgress={item.progress}
                  onClaim={handleClaim}
                />
              ))}
            </div>
          </div>
        )}

        {storyQuests.length > 0 && (
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-white mb-4">Story Quests</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {storyQuests.map((item) => (
                <QuestCard
                  key={item.quest.id}
                  questProgress={item.progress}
                  onStart={handleStart}
                  onClaim={handleClaim}
                />
              ))}
            </div>
          </div>
        )}

        {tutorialQuests.length === 0 && dailyQuests.length === 0 && weeklyQuests.length === 0 && storyQuests.length === 0 && (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg">No quests available</p>
            <p className="text-slate-400 mt-2">Check back later for new quests!</p>
          </div>
        )}
      </div>
    </div>
  );
}

