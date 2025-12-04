'use client';

import { useEffect, useState } from 'react';
import { useMiningStore } from '@/stores/useMiningStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { useAdEnergyRestore } from '@/hooks/useAdEnergyRestore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { getItemIcon, getItemName } from '@/lib/itemUtils';
import Tooltip from '@/components/ui/Tooltip';
import { getMiningToolTooltip, getActionTooltip } from '@/lib/tooltipUtils';

export default function MinePage() {
  const {
    mineDig,
    tools,
    oreTypes,
    loading,
    fetchMineDig,
    fetchTools,
    fetchOreTypes,
    mineOre,
    repairTool,
    upgradeTool,
    restoreEnergyWithCrystals,
    subscribeToMining
  } = useMiningStore();
  const { watchAdForEnergyRestore, canWatchAd, adsRemaining, loading: adLoading } = useAdEnergyRestore();
  const { crystals } = usePlayerStore();
  const [selectedTool, setSelectedTool] = useState<string>('basic_pickaxe');
  const [restoringEnergy, setRestoringEnergy] = useState(false);
  const [showRepairModal, setShowRepairModal] = useState<string | null>(null);
  const [showUpgradeModal, setShowUpgradeModal] = useState<string | null>(null);

  useEffect(() => {
    fetchMineDig();
    fetchTools();
    fetchOreTypes();
    const unsubscribe = subscribeToMining();
    return unsubscribe;
  }, [fetchMineDig, fetchTools, fetchOreTypes, subscribeToMining]);

  const maxEnergy = 100;
  const currentEnergy = mineDig ? maxEnergy - mineDig.energy_used_today : maxEnergy;
  const selectedToolData = tools.find(t => t.tool_type === selectedTool);

  const getToolName = (toolType: string): string => {
    const names: Record<string, string> = {
      'basic_pickaxe': 'Basic Pickaxe',
      'iron_pickaxe': 'Iron Pickaxe',
      'diamond_pickaxe': 'Diamond Pickaxe',
      'magic_pickaxe': 'Magic Pickaxe'
    };
    return names[toolType] || toolType;
  };

  const getToolIcon = (toolType: string): string => {
    const icons: Record<string, string> = {
      'basic_pickaxe': '⛏️',
      'iron_pickaxe': '🔨',
      'diamond_pickaxe': '💎',
      'magic_pickaxe': '✨'
    };
    return icons[toolType] || '⛏️';
  };

  const getNextTool = (toolType: string): string | null => {
    const next: Record<string, string> = {
      'basic_pickaxe': 'iron_pickaxe',
      'iron_pickaxe': 'diamond_pickaxe',
      'diamond_pickaxe': 'magic_pickaxe'
    };
    return next[toolType] || null;
  };

  const getUpgradeCost = (toolType: string): number => {
    const costs: Record<string, number> = {
      'basic_pickaxe': 500,
      'iron_pickaxe': 2000,
      'diamond_pickaxe': 5000
    };
    return costs[toolType] || 0;
  };

  const getRepairCost = (durability: number): number => {
    return (100 - durability) * 10;
  };

  const handleMine = async () => {
    try {
      await mineOre(selectedTool);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleRepair = async (toolType: string) => {
    try {
      await repairTool(toolType);
      setShowRepairModal(null);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleUpgrade = async (toolType: string) => {
    try {
      await upgradeTool(toolType);
      setShowUpgradeModal(null);
      const nextTool = getNextTool(toolType);
      if (nextTool) {
        setSelectedTool(nextTool);
      }
    } catch (error) {
      // Error handled in store
    }
  };

  const handleWatchAdForEnergy = async () => {
    try {
      await watchAdForEnergyRestore();
      await fetchMineDig(); // Refresh mining state
    } catch (error) {
      // Error handled in hook
    }
  };

  const handleRestoreEnergyWithCrystals = async () => {
    if (restoringEnergy) return;
    setRestoringEnergy(true);
    try {
      await restoreEnergyWithCrystals();
      await fetchMineDig(); // Refresh mining state
    } catch (error) {
      // Error handled in store
    } finally {
      setRestoringEnergy(false);
    }
  };

  const CRYSTAL_COST = 50;

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Mine</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-zinc-900 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Mine</h1>

        {/* Energy Bar */}
        <Tooltip
          content={[
            {
              title: 'Mining Energy',
              icon: '⚡',
              color: 'blue' as const,
              content: (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <span>Current:</span>
                    <span className="font-bold text-cyan-300">{currentEnergy} / {maxEnergy}</span>
                  </div>
                  <div className="border-t border-slate-700 pt-2 mt-2">
                    <p className="text-xs">• Each dig costs 10 energy</p>
                    <p className="text-xs">• Energy resets daily</p>
                    <p className="text-xs">• Restore with ads or crystals</p>
                  </div>
                </div>
              ),
            },
          ]}
          position="bottom"
        >
          <div className="mb-6 bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
            <div className="flex items-center justify-between mb-2">
              <span className="text-white font-semibold">Energy</span>
              <div className="flex items-center gap-3">
                <span className="text-white font-mono">{currentEnergy} / {maxEnergy}</span>
                {canWatchAd && currentEnergy < maxEnergy && (
                  <Tooltip content={getActionTooltip(`Watch Ad (${adsRemaining} remaining)`, undefined, ['Free energy restore', `${adsRemaining} ads remaining today`, 'No cost required'])} position="bottom">
                    <button
                      onClick={handleWatchAdForEnergy}
                      disabled={adLoading}
                      className="px-3 py-1 bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed text-white text-xs rounded-lg font-semibold transition-colors"
                    >
                      📺 Restore ({adsRemaining})
                    </button>
                  </Tooltip>
                )}
                {currentEnergy < maxEnergy && (
                  <Tooltip content={getActionTooltip('Restore Energy', CRYSTAL_COST, ['Instantly restore all energy', 'Costs crystals', 'No daily limit'])} position="bottom">
                    <button
                      onClick={handleRestoreEnergyWithCrystals}
                      disabled={restoringEnergy || crystals < CRYSTAL_COST}
                      className={`px-3 py-1 text-white text-xs rounded-lg font-semibold transition-colors ${
                        crystals < CRYSTAL_COST || restoringEnergy
                          ? 'bg-gray-600 cursor-not-allowed'
                          : 'bg-purple-600 hover:bg-purple-500'
                      }`}
                    >
                      💎 Restore ({CRYSTAL_COST})
                    </button>
                  </Tooltip>
                )}
              </div>
            </div>
            <div className="w-full bg-slate-800/60 rounded-full h-4 overflow-hidden">
              <div
                className={`h-full transition-all duration-300 ${
                  currentEnergy > 50 ? 'bg-green-500' : currentEnergy > 20 ? 'bg-yellow-500' : 'bg-red-500'
                }`}
                style={{ width: `${(currentEnergy / maxEnergy) * 100}%` }}
              />
            </div>
          </div>
        </Tooltip>

        {/* Mining Stats */}
        {mineDig && (
          <div className="mb-6 grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20">
              <div className="text-slate-300 text-sm mb-1">Current Depth</div>
              <div className="text-white text-2xl font-bold">{mineDig.depth}m</div>
            </div>
            <div className="bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20">
              <div className="text-slate-300 text-sm mb-1">Total Digs</div>
              <div className="text-white text-2xl font-bold">{mineDig.total_digs}</div>
            </div>
            <div className="bg-white/10 backdrop-blur-md rounded-xl p-4 border border-white/20">
              <div className="text-slate-300 text-sm mb-1">Artifacts Found</div>
              <div className="text-white text-2xl font-bold">{mineDig.artifacts.length}</div>
            </div>
          </div>
        )}

        {/* Tools Selection */}
        <div className="mb-6">
          <h2 className="text-xl font-bold text-white mb-4">Mining Tools</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {tools.map((tool) => (
              <Tooltip
                key={tool.id}
                content={getMiningToolTooltip(tool, getNextTool(tool.tool_type) ? getUpgradeCost(tool.tool_type) : undefined)}
                position="top"
              >
                <div
                  className={`bg-gradient-to-br ${
                    selectedTool === tool.tool_type
                      ? 'from-blue-600 to-indigo-600 border-2 border-blue-400'
                      : 'from-slate-800 to-slate-900 border-2 border-slate-700'
                  } rounded-xl p-4 cursor-pointer transition-all`}
                  onClick={() => setSelectedTool(tool.tool_type)}
                >
                <div className="flex items-center justify-between mb-2">
                  <span className="text-3xl">{getToolIcon(tool.tool_type)}</span>
                  <span className="text-white text-sm font-semibold">{getToolName(tool.tool_type)}</span>
                </div>
                <div className="mb-2">
                  <div className="text-slate-300 text-xs mb-1">Durability</div>
                  <div className="w-full bg-slate-800/60 rounded-full h-2 overflow-hidden">
                    <div
                      className={`h-full transition-all ${
                        tool.durability > 50 ? 'bg-green-500' : tool.durability > 20 ? 'bg-yellow-500' : 'bg-red-500'
                      }`}
                      style={{ width: `${tool.durability}%` }}
                    />
                  </div>
                  <div className="text-white text-xs mt-1">{tool.durability}%</div>
                </div>
                <div className="flex gap-2 mt-2">
                  {tool.durability < 100 && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowRepairModal(tool.tool_type);
                      }}
                      className="flex-1 px-2 py-1 bg-yellow-600 hover:bg-yellow-500 text-white rounded text-xs font-semibold transition-colors"
                    >
                      Repair
                    </button>
                  )}
                  {getNextTool(tool.tool_type) && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setShowUpgradeModal(tool.tool_type);
                      }}
                      className="flex-1 px-2 py-1 bg-green-600 hover:bg-green-500 text-white rounded text-xs font-semibold transition-colors"
                    >
                      Upgrade
                    </button>
                  )}
                </div>
              </div>
              </Tooltip>
            ))}
          </div>
        </div>

        {/* Mine Button */}
        <div className="mb-6 text-center">
          <Tooltip
            content={getActionTooltip(
              'Mine Ore',
              10,
              ['Dig for ores and minerals', 'Costs 10 energy per dig', 'Tool durability decreases', 'Higher level tools = better drops']
            )}
            position="top"
          >
            <button
              onClick={handleMine}
              disabled={!selectedToolData || selectedToolData.durability <= 0 || currentEnergy < 10}
              className={`px-8 py-4 rounded-xl font-bold text-xl transition-all ${
                !selectedToolData || selectedToolData.durability <= 0 || currentEnergy < 10
                  ? 'bg-gray-600 text-gray-400 cursor-not-allowed'
                  : 'bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-500 hover:to-red-500 text-white shadow-lg hover:scale-105'
              }`}
            >
              <span className="text-2xl mr-2">⛏️</span>
              Mine Ore
            </button>
          </Tooltip>
          {selectedToolData && selectedToolData.durability <= 0 && (
            <p className="text-red-400 text-sm mt-2">Tool is broken! Repair it first.</p>
          )}
          {currentEnergy < 10 && (
            <p className="text-yellow-400 text-sm mt-2">Not enough energy! Wait for daily reset.</p>
          )}
        </div>

        {/* Recent Artifacts */}
        {mineDig && mineDig.artifacts.length > 0 && (
          <div className="mb-6">
            <h2 className="text-xl font-bold text-white mb-4">Recent Finds</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
              {mineDig.artifacts.slice(-12).reverse().map((artifact, index) => (
                <div
                  key={index}
                  className="bg-white/10 backdrop-blur-md rounded-lg p-3 border border-white/20 text-center"
                >
                  <div className="text-3xl mb-1">{getItemIcon(artifact.item_id)}</div>
                  <div className="text-white text-xs font-semibold">{artifact.name}</div>
                  <div className="text-slate-400 text-xs">{artifact.depth}m</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Ore Types Reference */}
        <div>
          <h2 className="text-xl font-bold text-white mb-4">Ore Types</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
            {oreTypes.map((ore) => (
              <div
                key={ore.id}
                className={`bg-gradient-to-br ${
                  ore.rarity === 'epic' ? 'from-purple-600 to-pink-600' :
                  ore.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                  'from-gray-600 to-slate-600'
                } rounded-xl p-4 border border-white/20`}
              >
                <div className="text-center">
                  <div className="text-4xl mb-2">{ore.icon}</div>
                  <div className="text-white font-semibold mb-1">{ore.name}</div>
                  <div className="text-yellow-400 text-sm">💎 {ore.base_value_crystals}</div>
                  <div className="text-white/80 text-xs capitalize mt-1">{ore.rarity}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Repair Modal */}
        {showRepairModal && selectedToolData && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowRepairModal(null)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Repair Tool</h3>
              <div className="mb-4">
                <p className="text-slate-300 mb-2">Tool: {getToolName(showRepairModal)}</p>
                <p className="text-slate-300 mb-2">Current Durability: {selectedToolData.durability}%</p>
                <p className="text-yellow-400 font-semibold">Cost: 💎 {getRepairCost(selectedToolData.durability).toLocaleString()}</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => setShowRepairModal(null)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={() => handleRepair(showRepairModal)}
                  className="flex-1 px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-white rounded-lg font-semibold transition-colors"
                >
                  Repair
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Upgrade Modal */}
        {showUpgradeModal && selectedToolData && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowUpgradeModal(null)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Upgrade Tool</h3>
              <div className="mb-4">
                <p className="text-slate-300 mb-2">Current: {getToolName(showUpgradeModal)}</p>
                <p className="text-slate-300 mb-2">Upgrade To: {getToolName(getNextTool(showUpgradeModal) || '')}</p>
                <p className="text-yellow-400 font-semibold">Cost: 💎 {getUpgradeCost(showUpgradeModal).toLocaleString()}</p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => setShowUpgradeModal(null)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={() => handleUpgrade(showUpgradeModal)}
                  className="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
                >
                  Upgrade
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

