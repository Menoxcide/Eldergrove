'use client';

import React from 'react';
import { Recipe } from '@/stores/useFactoryStore';
import { getItemIcon } from '@/lib/itemUtils';
import { getItemName } from '@/stores/useInventoryStore';

interface RecipeCardProps {
  recipe: Recipe;
  canCraft: boolean;
  onStart: () => void;
  inventory: Array<{ item_id: number; quantity: number }>;
}

const RecipeCard: React.FC<RecipeCardProps> = ({ recipe, canCraft, onStart, inventory }) => {
  const itemNameToId: Record<string, number> = {
    'wheat': 1,
    'carrot': 2,
    'potato': 3,
    'tomato': 4,
    'corn': 5,
    'pumpkin': 6,
    'bread': 8,
    'berry': 11,
    'herbs': 12,
    'magic_mushroom': 13,
    'enchanted_flower': 14
  };

  const getItemId = (itemName: string): number => {
    return itemNameToId[itemName.toLowerCase()] || 0;
  };

  const getAvailableQuantity = (itemId: number): number => {
    const item = inventory.find(inv => inv.item_id === itemId);
    return item?.quantity || 0;
  };

  return (
    <div className={`bg-white/10 backdrop-blur-md rounded-2xl p-6 border-2 transition-all ${
      canCraft ? 'border-green-500/50 hover:border-green-400' : 'border-red-500/30 opacity-75'
    }`}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-xl font-bold text-white">{recipe.name}</h3>
        <span className="text-yellow-400 text-sm">⏱ {recipe.minutes}m</span>
      </div>

      <div className="mb-4">
        <div className="text-sm text-slate-300 mb-2">Required:</div>
        <div className="flex flex-wrap gap-2">
          {Object.entries(recipe.input).map(([itemName, requiredQty]) => {
            const itemId = getItemId(itemName);
            const availableQty = getAvailableQuantity(itemId);
            const hasEnough = availableQty >= requiredQty;
            
            return (
              <div
                key={itemName}
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
          {Object.entries(recipe.output).map(([itemName, qty]) => {
            const itemId = itemName === 'crystals' ? 3 : getItemId(itemName);
            return (
              <div key={itemName} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-blue-900/50">
                <span className="text-lg">{itemName === 'crystals' ? '💎' : getItemIcon(itemId)}</span>
                <span className="text-xs text-white">
                  {qty} {itemName === 'crystals' ? 'Crystals' : getItemName(itemId)}
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
        {canCraft ? 'Start Production' : 'Insufficient Materials'}
      </button>
    </div>
  );
};

export default RecipeCard;

