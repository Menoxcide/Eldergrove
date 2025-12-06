import { TooltipSection } from '@/components/ui/Tooltip';
import { getItemName, getItemIcon, getItemCategory, getCategoryName } from '@/lib/itemUtils';

// Resource Tooltips
export const getCrystalsTooltip = (crystals: number, level: number): TooltipSection[] => {
  return [
    {
      title: 'Crystals',
      icon: '💎',
      color: 'blue',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Current:</span>
            <span className="font-bold text-cyan-300">{crystals.toLocaleString()}</span>
          </div>
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">How to Earn:</div>
            <ul className="text-xs space-y-1 list-disc list-inside text-slate-300">
              <li>Harvest crops from your farm</li>
              <li>Complete skyport orders</li>
              <li>Sell items at the market</li>
              <li>Complete quests and achievements</li>
              <li>Watch ads for rewards</li>
            </ul>
          </div>
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">Common Uses:</div>
            <ul className="text-xs space-y-1 list-disc list-inside text-slate-300">
              <li>Purchase buildings and decorations</li>
              <li>Upgrade factories and armories</li>
              <li>Expand your town</li>
              <li>Restore energy and speed up production</li>
            </ul>
          </div>
        </div>
      ),
    },
  ];
};

export const getLevelTooltip = (level: number, xp: number): TooltipSection[] => {
  // Database formula: XP needed for next level = current_level * 1000
  // Level 1 -> 2: 1000 XP, Level 2 -> 3: 2000 XP, etc.
  const xpForNextLevel = level * 1000;
  const xpNeeded = Math.max(0, xpForNextLevel - xp);
  // Progress is calculated as: (current_xp % (level * 1000)) / (level * 1000) * 100
  // But since XP resets to 0 after leveling, we use: (xp % xpForNextLevel) / xpForNextLevel * 100
  const progress = xpForNextLevel > 0 ? ((xp % xpForNextLevel) / xpForNextLevel) * 100 : 0;

  return [
    {
      title: 'Player Level',
      icon: '👑',
      color: 'yellow',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Current Level:</span>
            <span className="font-bold text-yellow-300">Level {level}</span>
          </div>
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">Progress to Next Level:</div>
            <div className="w-full bg-slate-700 rounded-full h-2 mb-1">
              <div
                className="bg-yellow-500 h-2 rounded-full transition-all"
                style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
              />
            </div>
            <div className="flex justify-between text-xs">
              <span>{(xp % xpForNextLevel).toLocaleString()} / {xpForNextLevel.toLocaleString()} XP</span>
              <span className="text-yellow-400">{xpNeeded > 0 ? `${xpNeeded.toLocaleString()} more` : 'Ready to Level Up!'}</span>
            </div>
          </div>
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">How to Gain XP:</div>
            <ul className="text-xs space-y-1 list-disc list-inside text-slate-300">
              <li>Harvest crops and complete production</li>
              <li>Fulfill skyport orders</li>
              <li>Complete quests and achievements</li>
              <li>Build and upgrade structures</li>
            </ul>
          </div>
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">Level Benefits:</div>
            <ul className="text-xs space-y-1 list-disc list-inside text-slate-300">
              <li>Unlock new buildings and features</li>
              <li>Access higher-tier recipes</li>
              <li>Increase town expansion limits</li>
              <li>Earn daily reward bonuses</li>
            </ul>
          </div>
        </div>
      ),
    },
  ];
};

export const getXPTooltip = (xp: number, level: number): TooltipSection[] => {
  // Database formula: XP needed for next level = current_level * 1000
  const xpForNextLevel = level * 1000;
  const xpNeeded = Math.max(0, xpForNextLevel - xp);

  return [
    {
      title: 'Experience Points',
      icon: '⭐',
      color: 'yellow',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Current XP:</span>
            <span className="font-bold text-yellow-300">{xp.toLocaleString()}</span>
          </div>
          {xpNeeded > 0 && (
            <div className="flex items-center justify-between text-xs">
              <span>XP to Next Level:</span>
              <span className="text-yellow-400 font-semibold">{xpNeeded.toLocaleString()}</span>
            </div>
          )}
          <div className="border-t border-slate-700 pt-2 mt-2">
            <div className="text-xs font-semibold mb-1">XP Sources:</div>
            <ul className="text-xs space-y-1 list-disc list-inside text-slate-300">
              <li>Harvesting crops: 5-20 XP per harvest</li>
              <li>Completing production: 10-50 XP per item</li>
              <li>Fulfilling orders: 25-100 XP per order</li>
              <li>Completing quests: 50-500 XP per quest</li>
              <li>Building structures: 100+ XP per building</li>
            </ul>
          </div>
        </div>
      ),
    },
  ];
};

// Item Tooltips
export const getItemTooltip = (
  itemId: number,
  quantity: number,
  storageUsage?: { used: number; capacity: number }
): TooltipSection[] => {
  const name = getItemName(itemId);
  const icon = getItemIcon(itemId);
  const category = getItemCategory(itemId);
  const categoryName = getCategoryName(category);

  const sections: TooltipSection[] = [
    {
      title: name,
      icon: icon,
      color: 'blue',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Quantity:</span>
            <span className="font-bold text-cyan-300">{quantity.toLocaleString()}</span>
          </div>
          <div className="flex items-center justify-between text-xs">
            <span>Category:</span>
            <span className="text-slate-300">{categoryName}</span>
          </div>
          {storageUsage && (
            <div className="flex items-center justify-between text-xs">
              <span>Storage:</span>
              <span className="text-slate-300">
                {storageUsage.used}/{storageUsage.capacity} slots
              </span>
            </div>
          )}
        </div>
      ),
    },
  ];

  // Add category-specific information
  if (category === 'crops') {
    sections.push({
      title: 'Usage',
      icon: '🌾',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Use in factory recipes to create products</p>
          <p>• Sell at the market for crystals</p>
          <p>• Fulfill skyport orders for rewards</p>
          <p>• Required for various quests</p>
        </div>
      ),
    });
    sections.push({
      title: 'How to Obtain',
      icon: '🌱',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Plant seeds in farm plots and harvest when ready</p>
          <p>• Purchase from the seed shop</p>
          <p>• Receive as rewards from orders and quests</p>
        </div>
      ),
    });
  } else if (category === 'seeds') {
    sections.push({
      title: 'Usage',
      icon: '🌱',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Plant in empty farm plots to grow crops</p>
          <p>• Each seed produces one crop when harvested</p>
          <p>• Seeds are consumed when planting</p>
        </div>
      ),
    });
    sections.push({
      title: 'How to Obtain',
      icon: '🛒',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Purchase from the seed shop with crystals</p>
          <p>• Receive as rewards from quests</p>
          <p>• Sometimes found in premium shop bundles</p>
        </div>
      ),
    });
  } else if (category === 'ore') {
    sections.push({
      title: 'Usage',
      icon: '⛏️',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Craft equipment in the armory</p>
          <p>• Sell at the market for crystals</p>
          <p>• Required for high-tier recipes</p>
          <p>• Used in building upgrades</p>
        </div>
      ),
    });
    sections.push({
      title: 'How to Obtain',
      icon: '💎',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Mine in the mine using pickaxes</p>
          <p>• Rarer ores require higher-level tools</p>
          <p>• Drop rates increase with tool level</p>
        </div>
      ),
    });
  } else if (category === 'equipment') {
    sections.push({
      title: 'Usage',
      icon: '⚔️',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Equip to boost mining efficiency</p>
          <p>• Sell at the market for high crystal value</p>
          <p>• Required for advanced quests</p>
        </div>
      ),
    });
    sections.push({
      title: 'How to Obtain',
      icon: '🔨',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Craft in the armory using ores</p>
          <p>• Higher-tier equipment requires rare materials</p>
          <p>• Upgrade armories to unlock better recipes</p>
        </div>
      ),
    });
  } else if (category === 'production') {
    sections.push({
      title: 'Usage',
      icon: '🏭',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Sell at the market for crystals</p>
          <p>• Fulfill skyport orders</p>
          <p>• Use in advanced recipes</p>
          <p>• Required for quests</p>
        </div>
      ),
    });
    sections.push({
      title: 'How to Obtain',
      icon: '🍞',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Craft in factories using crops and materials</p>
          <p>• Production time varies by recipe</p>
          <p>• Upgrade factories to unlock more recipes</p>
        </div>
      ),
    });
  }

  return sections;
};

// Crop Tooltips
export const getCropTooltip = (
  crop: { id: number; name: string; grow_minutes: number; yield_crystals: number; item_id: number },
  seedCount?: number
): TooltipSection[] => {
  const sections: TooltipSection[] = [
    {
      title: crop.name,
      icon: getItemIcon(crop.item_id),
      color: 'green',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Grow Time:</span>
            <span className="font-bold text-emerald-300">{crop.grow_minutes} minutes</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Crystal Yield:</span>
            <span className="font-bold text-yellow-300">💎 {crop.yield_crystals}</span>
          </div>
          {seedCount !== undefined && (
            <div className="flex items-center justify-between">
              <span>Seeds Available:</span>
              <span className={`font-bold ${seedCount > 0 ? 'text-green-300' : 'text-red-300'}`}>
                {seedCount}
              </span>
            </div>
          )}
        </div>
      ),
    },
    {
      title: 'Rewards',
      icon: '🎁',
      color: 'yellow',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Earn {crop.yield_crystals} crystals when harvested</p>
          <p>• Gain 5-20 XP per harvest</p>
          <p>• Receive 1 {getItemName(crop.item_id)} item</p>
          <p>• Can be used in factory recipes</p>
        </div>
      ),
    },
    {
      title: 'Tips',
      icon: '💡',
      color: 'purple',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Plant multiple plots for faster production</p>
          <p>• Use speed-ups to harvest faster</p>
          <p>• Watch ads for free 30-minute speed-ups</p>
          <p>• Higher-tier crops take longer but yield more</p>
        </div>
      ),
    },
  ];

  return sections;
};

// Building Tooltips
export const getBuildingTooltip = (
  buildingType: { name: string; category: string; base_cost_crystals: number; provides_population: number; population_required: number },
  level?: number
): TooltipSection[] => {
  const sections: TooltipSection[] = [
    {
      title: buildingType.name,
      icon: '🏛️',
      color: 'blue',
      content: (
        <div className="space-y-2">
          {level !== undefined && (
            <div className="flex items-center justify-between">
              <span>Level:</span>
              <span className="font-bold text-cyan-300">Level {level}</span>
            </div>
          )}
          <div className="flex items-center justify-between">
            <span>Category:</span>
            <span className="text-slate-300 capitalize">{buildingType.category}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Base Cost:</span>
            <span className="font-bold text-yellow-300">💎 {buildingType.base_cost_crystals.toLocaleString()}</span>
          </div>
        </div>
      ),
    },
  ];

  if (buildingType.provides_population > 0) {
    sections.push({
      title: 'Benefits',
      icon: '👥',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Provides {buildingType.provides_population} population</p>
          <p>• Increases town capacity</p>
          <p>• Unlocks new features and buildings</p>
        </div>
      ),
    });
  }

  if (buildingType.population_required > 0) {
    sections.push({
      title: 'Requirements',
      icon: '⚠️',
      color: 'red',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Requires {buildingType.population_required} population</p>
          <p>• Build other structures first to meet requirement</p>
        </div>
      ),
    });
  }

  sections.push({
    title: 'Usage',
    icon: '🏗️',
    color: 'purple',
    content: (
      <div className="space-y-1 text-xs">
        <p>• Place on your town map</p>
        <p>• Upgrade to increase benefits</p>
        <p>• Some buildings unlock new features</p>
      </div>
    ),
  });

  return sections;
};

// Recipe Tooltips
export const getRecipeTooltip = (
  recipe: { name: string; minutes: number; input: Record<string, number>; output: Record<string, number> },
  canCraft: boolean,
  inventory: Array<{ item_id: number; quantity: number }>
): TooltipSection[] => {
  const itemNameToId: Record<string, number> = {
    'wheat': 1, 'carrot': 2, 'potato': 3, 'tomato': 4, 'corn': 5,
    'pumpkin': 6, 'bread': 8, 'berry': 11, 'herbs': 12,
    'magic_mushroom': 13, 'enchanted_flower': 14
  };

  const getItemId = (itemName: string): number => {
    return itemNameToId[itemName.toLowerCase()] || 0;
  };

  const sections: TooltipSection[] = [
    {
      title: recipe.name,
      icon: '📜',
      color: 'blue',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Production Time:</span>
            <span className="font-bold text-cyan-300">{recipe.minutes} minutes</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Status:</span>
            <span className={`font-bold ${canCraft ? 'text-green-300' : 'text-red-300'}`}>
              {canCraft ? 'Ready' : 'Missing Materials'}
            </span>
          </div>
        </div>
      ),
    },
    {
      title: 'Required Materials',
      icon: '📦',
      color: canCraft ? 'green' : 'red',
      content: (
        <div className="space-y-1 text-xs">
          {Object.entries(recipe.input).map(([itemName, requiredQty]) => {
            const itemId = getItemId(itemName);
            const inventoryItem = inventory.find(inv => inv.item_id === itemId);
            const availableQty = inventoryItem?.quantity || 0;
            const hasEnough = availableQty >= requiredQty;
            return (
              <div key={itemName} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{getItemIcon(itemId)}</span>
                  <span>{getItemName(itemId)}:</span>
                </span>
                <span className={hasEnough ? 'text-green-300' : 'text-red-300'}>
                  {availableQty}/{requiredQty}
                </span>
              </div>
            );
          })}
        </div>
      ),
    },
    {
      title: 'Produces',
      icon: '✨',
      color: 'yellow',
      content: (
        <div className="space-y-1 text-xs">
          {Object.entries(recipe.output).map(([itemName, qty]) => {
            const itemId = itemName === 'crystals' ? 18 : getItemId(itemName);
            return (
              <div key={itemName} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{itemName === 'crystals' ? '💎' : getItemIcon(itemId)}</span>
                  <span>{itemName === 'crystals' ? 'Crystals' : getItemName(itemId)}:</span>
                </span>
                <span className="text-yellow-300 font-semibold">+{qty}</span>
              </div>
            );
          })}
        </div>
      ),
    },
  ];

  return sections;
};

// Armory Recipe Tooltips
export const getArmoryRecipeTooltip = (
  recipe: { name: string; minutes: number; input: Record<string, number>; output: Record<string, number> },
  canCraft: boolean,
  inventory: Array<{ item_id: number; quantity: number }>
): TooltipSection[] => {
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

  const sections: TooltipSection[] = [
    {
      title: recipe.name,
      icon: '⚔️',
      color: 'blue',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Crafting Time:</span>
            <span className="font-bold text-cyan-300">{recipe.minutes} minutes</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Status:</span>
            <span className={`font-bold ${canCraft ? 'text-green-300' : 'text-red-300'}`}>
              {canCraft ? 'Ready' : 'Missing Materials'}
            </span>
          </div>
        </div>
      ),
    },
    {
      title: 'Required Ore',
      icon: '⛏️',
      color: canCraft ? 'green' : 'red',
      content: (
        <div className="space-y-1 text-xs">
          {Object.entries(recipe.input).map(([oreName, requiredQty]) => {
            const itemId = getOreItemId(oreName);
            const inventoryItem = inventory.find(inv => inv.item_id === itemId);
            const availableQty = inventoryItem?.quantity || 0;
            const hasEnough = availableQty >= requiredQty;
            return (
              <div key={oreName} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{getItemIcon(itemId)}</span>
                  <span>{getItemName(itemId)}:</span>
                </span>
                <span className={hasEnough ? 'text-green-300' : 'text-red-300'}>
                  {availableQty}/{requiredQty}
                </span>
              </div>
            );
          })}
        </div>
      ),
    },
    {
      title: 'Produces',
      icon: '✨',
      color: 'yellow',
      content: (
        <div className="space-y-1 text-xs">
          {Object.entries(recipe.output).map(([equipmentName, qty]) => {
            const itemId = getEquipmentItemId(equipmentName);
            return (
              <div key={equipmentName} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{getItemIcon(itemId)}</span>
                  <span>{getItemName(itemId)}:</span>
                </span>
                <span className="text-yellow-300 font-semibold">+{qty}</span>
              </div>
            );
          })}
        </div>
      ),
    },
  ];

  return sections;
};

// Button/Action Tooltips
export const getActionTooltip = (
  action: string,
  cost?: number,
  requirements?: string[],
  cooldown?: number
): TooltipSection[] => {
  const sections: TooltipSection[] = [
    {
      title: action,
      icon: '⚡',
      color: 'blue',
      content: (
        <div className="space-y-1 text-xs">
          {cost !== undefined && (
            <div className="flex items-center justify-between">
              <span>Cost:</span>
              <span className="font-bold text-yellow-300">💎 {cost.toLocaleString()}</span>
            </div>
          )}
          {cooldown !== undefined && (
            <div className="flex items-center justify-between">
              <span>Cooldown:</span>
              <span className="font-bold text-purple-300">{cooldown} minutes</span>
            </div>
          )}
        </div>
      ),
    },
  ];

  if (requirements && requirements.length > 0) {
    sections.push({
      title: 'Requirements',
      icon: '⚠️',
      color: 'red',
      content: (
        <div className="space-y-1 text-xs">
          {requirements.map((req, idx) => (
            <p key={idx}>• {req}</p>
          ))}
        </div>
      ),
    });
  }

  return sections;
};

// Mining Tool Tooltips
export const getMiningToolTooltip = (
  tool: { tool_type: string; level: number; durability: number },
  upgradeCost?: number
): TooltipSection[] => {
  const toolNames: Record<string, string> = {
    'basic_pickaxe': 'Basic Pickaxe',
    'iron_pickaxe': 'Iron Pickaxe',
    'diamond_pickaxe': 'Diamond Pickaxe',
    'magic_pickaxe': 'Magic Pickaxe',
  };

  const sections: TooltipSection[] = [
    {
      title: toolNames[tool.tool_type] || tool.tool_type,
      icon: '⛏️',
      color: 'blue',
      content: (
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <span>Level:</span>
            <span className="font-bold text-cyan-300">Level {tool.level}</span>
          </div>
          <div className="flex items-center justify-between">
            <span>Durability:</span>
            <span className={`font-bold ${tool.durability > 50 ? 'text-green-300' : tool.durability > 20 ? 'text-yellow-300' : 'text-red-300'}`}>
              {tool.durability}%
            </span>
          </div>
          {upgradeCost !== undefined && (
            <div className="flex items-center justify-between">
              <span>Upgrade Cost:</span>
              <span className="font-bold text-yellow-300">💎 {upgradeCost.toLocaleString()}</span>
            </div>
          )}
        </div>
      ),
    },
    {
      title: 'Efficiency',
      icon: '⚡',
      color: 'green',
      content: (
        <div className="space-y-1 text-xs">
          <p>• Higher level = better ore drop rates</p>
          <p>• Durability decreases with each dig</p>
          <p>• Repair tools to restore durability</p>
          <p>• Upgrade for access to rarer ores</p>
        </div>
      ),
    },
  ];

  return sections;
};

// Order Tooltips
export const getOrderTooltip = (
  order: { order_type: string; requirements: Record<string, number>; rewards: { crystals?: number; xp?: number; items?: Record<string, number> }; expires_at: string },
  inventory: Array<{ item_id: number; quantity: number }>
): TooltipSection[] => {
  const orderTypeNames: Record<string, string> = {
    'quick': 'Quick Order',
    'standard': 'Standard Order',
    'premium': 'Premium Order',
  };

  const orderTypeDescriptions: Record<string, string> = {
    'quick': 'Fast delivery, moderate rewards',
    'standard': 'Standard delivery time, good rewards',
    'premium': 'Longer time, excellent rewards',
  };

  const sections: TooltipSection[] = [
    {
      title: orderTypeNames[order.order_type] || 'Order',
      icon: '📦',
      color: 'blue',
      content: (
        <div className="space-y-2">
          <p className="text-xs text-slate-300">{orderTypeDescriptions[order.order_type]}</p>
          <div className="flex items-center justify-between text-xs">
            <span>Expires:</span>
            <span className="text-red-300">
              {Math.ceil((new Date(order.expires_at).getTime() - Date.now()) / 1000 / 60)} minutes
            </span>
          </div>
        </div>
      ),
    },
    {
      title: 'Required Items',
      icon: '📋',
      color: 'red',
      content: (
        <div className="space-y-1 text-xs">
          {Object.entries(order.requirements).map(([itemIdStr, requiredQty]) => {
            const itemId = parseInt(itemIdStr);
            const inventoryItem = inventory.find(inv => inv.item_id === itemId);
            const availableQty = inventoryItem?.quantity || 0;
            const hasEnough = availableQty >= requiredQty;
            return (
              <div key={itemId} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{getItemIcon(itemId)}</span>
                  <span>{getItemName(itemId)}:</span>
                </span>
                <span className={hasEnough ? 'text-green-300' : 'text-red-300'}>
                  {availableQty}/{requiredQty}
                </span>
              </div>
            );
          })}
        </div>
      ),
    },
    {
      title: 'Rewards',
      icon: '🎁',
      color: 'yellow',
      content: (
        <div className="space-y-1 text-xs">
          {order.rewards.crystals && (
            <div className="flex items-center justify-between">
              <span>💎 Crystals:</span>
              <span className="text-yellow-300 font-semibold">+{order.rewards.crystals}</span>
            </div>
          )}
          {order.rewards.xp && (
            <div className="flex items-center justify-between">
              <span>⭐ XP:</span>
              <span className="text-yellow-300 font-semibold">+{order.rewards.xp}</span>
            </div>
          )}
          {order.rewards.items && Object.entries(order.rewards.items).map(([itemIdStr, qty]) => {
            const itemId = parseInt(itemIdStr);
            return (
              <div key={itemId} className="flex items-center justify-between">
                <span className="flex items-center gap-1">
                  <span>{getItemIcon(itemId)}</span>
                  <span>{getItemName(itemId)}:</span>
                </span>
                <span className="text-yellow-300 font-semibold">+{qty}</span>
              </div>
            );
          })}
        </div>
      ),
    },
  ];

  return sections;
};

