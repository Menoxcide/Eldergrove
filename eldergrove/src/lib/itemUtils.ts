// Shared utilities for item icons and names

export const getItemIcon = (itemId: number): string => {
  const iconMap: Record<number, string> = {
    1: '🌾',   // Wheat
    2: '🥕',   // Carrot
    3: '🥔',   // Potato
    4: '🍅',   // Tomato
    5: '🌽',   // Corn
    6: '🎃',   // Pumpkin
    7: '🍓',   // Berry
    8: '🌿',   // Herbs
    9: '🍄',   // Magic Mushroom
    10: '🌸',  // Enchanted Flower
    11: '🍞',  // Bread
    12: '🍲',  // Vegetable Stew
    13: '🥖',  // Corn Bread
    14: '🥧',  // Pumpkin Pie
    15: '🍵',  // Herbal Tea
    16: '🧪',  // Magic Potion
    17: '🥗',  // Fruit Salad
    18: '💎',  // Crystals
    // Ores (20-29)
    20: '⚫',  // Coal
    21: '🔩',  // Iron Ore
    22: '🟠',  // Copper Ore
    23: '⚪',  // Silver Ore
    24: '🟡',  // Gold Ore
    25: '💎',  // Crystal Shard
    26: '🔷',  // Mithril Ore
    27: '✨',  // Aether Crystal
    28: '🐉',  // Dragon Scale
    29: '🏺',  // Ancient Relic
  };
  return iconMap[itemId] || '📦';
};

export const getItemName = (itemId: number): string => {
  const itemNames: Record<number, string> = {
    1: 'Wheat',
    2: 'Carrot',
    3: 'Potato',
    4: 'Tomato',
    5: 'Corn',
    6: 'Pumpkin',
    7: 'Berry',
    8: 'Herbs',
    9: 'Magic Mushroom',
    10: 'Enchanted Flower',
    11: 'Bread',
    12: 'Vegetable Stew',
    13: 'Corn Bread',
    14: 'Pumpkin Pie',
    15: 'Herbal Tea',
    16: 'Magic Potion',
    17: 'Fruit Salad',
    18: 'Crystals',
    // Ores (20-29)
    20: 'Coal',
    21: 'Iron Ore',
    22: 'Copper Ore',
    23: 'Silver Ore',
    24: 'Gold Ore',
    25: 'Crystal Shard',
    26: 'Mithril Ore',
    27: 'Aether Crystal',
    28: 'Dragon Scale',
    29: 'Ancient Relic',
  };
  return itemNames[itemId] || `Item ${itemId}`;
};

