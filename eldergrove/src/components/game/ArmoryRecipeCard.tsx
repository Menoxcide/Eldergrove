'use client';

import React from 'react';
import { ArmoryRecipe } from '@/stores/useArmoryStore';
import { getItemIcon, getItemName } from '@/lib/itemUtils';
import Tooltip from '@/components/ui/Tooltip';
import { getArmoryRecipeTooltip } from '@/lib/tooltipUtils';

interface ArmoryRecipeCardProps {
  recipe: ArmoryRecipe;
  canCraft: boolean;
  onStart: () => void;
  inventory: Array<{ item_id: number; quantity: number }>;
}

const ArmoryRecipeCard: React.FC<ArmoryRecipeCardProps> = ({ recipe, canCraft, onStart, inventory }) => {
  const oreNameToId: Record<string, number> = {
    'coal': 20,
    'iron_ore': 21,
    'copper_ore': 22,
    'silver_ore': 23,
    'gold_ore': 24,
    'crystal_shard': 25,
    'mithril_ore': 26,
    'aether_crystal': 27,
    'dragon_scale': 28,
    'ancient_relic': 29
  };

  const equipmentNameToId: Record<string, number> = {
    'iron_sword': 30,
    'steel_blade': 31,
    'diamond_armor': 32,
    'mithril_sword': 33,
    'aether_blade': 34,
    'dragon_scale_armor': 35,
    'ancient_relic_weapon': 36
  };

  const getOreItemId = (oreName: string): number => {
    return oreNameToId[oreName.toLowerCase()] || 0;
  };

  const getEquipmentItemId = (equipmentName: string): number => {
    return equipmentNameToId[equipmentName.toLowerCase()] || 0;
  };

  const getAvailableQuantity = (itemId: number): number => {
    const item = inventory.find(inv => inv.item_id === itemId);
    return item?.quantity || 0;
  };

  return (
    <Tooltip content={getArmoryRecipeTooltip(recipe, canCraft, inventory)} position="top">
      <div className={`bg-white/10 backdrop-blur-md rounded-2xl p-6 border-2 transition-all ${
        canCraft ? 'border-green-500/50 hover:border-green-400' : 'border-red-500/30 opacity-75'
      }`}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-xl font-bold text-white">{recipe.name}</h3>
        <span className="text-yellow-400 text-sm">⏱ {recipe.minutes}m</span>
      </div>

      <div className="mb-4">
        <div className="text-sm text-slate-300 mb-2">Required Ore:</div>
        <div className="flex flex-wrap gap-2">
          {Object.entries(recipe.input).map(([oreName, requiredQty]) => {
            const itemId = getOreItemId(oreName);
            const availableQty = getAvailableQuantity(itemId);
            const hasEnough = availableQty >= requiredQty;
            
            return (
              <div
                key={oreName}
                className={`flex items-center gap-1 px-2 py-1 rounded-lg ${
                  hasEnough ? 'bg-green-900/50' : 'bg-red-900/50'
                }`}
              >
                <span className="text-lg">{getItemIcon(itemId)}</span>
                <span className={`text-xs ${hasEnough ? 'text-white' : 'text-red-300'}`}>
                  {requiredQty} {getItemName(itemId)}
                </span>
                {!hasEnough && (
                  <span className="text-xs text-red-400">({availableQty} available)</span>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="mb-4">
        <div className="text-sm text-slate-300 mb-2">Output:</div>
        <div className="flex flex-wrap gap-2">
          {Object.entries(recipe.output).map(([equipmentName, qty]) => {
            const itemId = getEquipmentItemId(equipmentName);
            return (
              <div key={equipmentName} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-blue-900/50">
                <span className="text-lg">{getItemIcon(itemId)}</span>
                <span className="text-xs text-white">
                  {qty} {getItemName(itemId)}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      <button
        onClick={onStart}
        disabled={!canCraft}
        className={`w-full py-2 rounded-lg font-semibold transition-colors ${
          canCraft
            ? 'bg-green-600 hover:bg-green-500 text-white'
            : 'bg-gray-600 text-gray-400 cursor-not-allowed'
        }`}
      >
        {canCraft ? 'Start Crafting' : 'Insufficient Materials'}
      </button>
    </div>
    </Tooltip>
  );
};

export default ArmoryRecipeCard;

