// Shared utilities for item icons and names

export const getItemIcon = (itemId: number): string => {
  const iconMap: Record<number, string> = {
    1: '🌾',   // Wheat
    2: '🥕',   // Carrot
    3: '🥔',   // Potato
    4: '🍅',   // Tomato
    5: '🌽',   // Corn
    6: '🎃',   // Pumpkin
    7: '🧪',   // Minor Healing Potion
    8: '🍞',   // Bread
    9: '✨',   // Magic Essence
    10: '🌱',  // Enchanted Seeds
    11: '🍓',  // Berry
    12: '🌿',  // Herbs
    13: '🍄',  // Magic Mushroom
    14: '🌸',  // Enchanted Flower
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
    // Equipment (30-39)
    30: '⚔️',  // Iron Sword
    31: '🗡️',  // Steel Blade
    32: '🛡️',  // Diamond Armor
    33: '⚔️',  // Mithril Sword
    34: '✨',  // Aether Blade
    35: '🐉',  // Dragon Scale Armor
    36: '🏺',  // Ancient Relic Weapon
    // Seeds (100-110)
    101: '🌾',  // Wheat Seed
    102: '🥕',  // Carrot Seed
    103: '🥔',  // Potato Seed
    104: '🍅',  // Tomato Seed
    105: '🌽',  // Corn Seed
    106: '🎃',  // Pumpkin Seed
    107: '🍓',  // Berry Seed
    108: '🌿',  // Herbs Seed
    109: '🍄',  // Magic Mushroom Seed
    110: '🌸',  // Enchanted Flower Seed
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
    7: 'Minor Healing Potion',
    8: 'Bread',
    9: 'Magic Essence',
    10: 'Enchanted Seeds',
    11: 'Berry',
    12: 'Herbs',
    13: 'Magic Mushroom',
    14: 'Enchanted Flower',
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
    // Equipment (30-39)
    30: 'Iron Sword',
    31: 'Steel Blade',
    32: 'Diamond Armor',
    33: 'Mithril Sword',
    34: 'Aether Blade',
    35: 'Dragon Scale Armor',
    36: 'Ancient Relic Weapon',
    // Seeds (100-110)
    101: 'Wheat Seed',
    102: 'Carrot Seed',
    103: 'Potato Seed',
    104: 'Tomato Seed',
    105: 'Corn Seed',
    106: 'Pumpkin Seed',
    107: 'Berry Seed',
    108: 'Herbs Seed',
    109: 'Magic Mushroom Seed',
    110: 'Enchanted Flower Seed',
  };
  return itemNames[itemId] || `Item ${itemId}`;
};

export type ItemCategory = 'seeds' | 'crops' | 'production' | 'ore' | 'equipment' | 'other';

export const getItemCategory = (itemId: number): ItemCategory => {
  // Seeds: 100-110 (crops 1-10) and 111-114 (crops 11-14)
  if ((itemId >= 100 && itemId <= 110) || (itemId >= 111 && itemId <= 114)) {
    return 'seeds';
  }
  
  // Crops: 1-6 (Wheat, Carrot, Potato, Tomato, Corn, Pumpkin) and 11-14 (Berry, Herbs, Magic Mushroom, Enchanted Flower)
  const cropIds = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14];
  if (cropIds.includes(itemId)) {
    return 'crops';
  }
  
  // Production items: 7-10 (Minor Healing Potion, Bread, Magic Essence, Enchanted Seeds) and 15-19 (Herbal Tea, Magic Potion, Fruit Salad, Crystals)
  const productionIds = [7, 8, 9, 10, 15, 16, 17, 18, 19];
  if (productionIds.includes(itemId)) {
    return 'production';
  }
  
  // Ore: 20-29
  if (itemId >= 20 && itemId <= 29) {
    return 'ore';
  }
  // Equipment: 30-39
  if (itemId >= 30 && itemId <= 39) {
    return 'equipment';
  }
  return 'other';
};

export const isSeed = (itemId: number): boolean => {
  return itemId >= 100 && itemId <= 110;
};

export const isCrop = (itemId: number): boolean => {
  // Crops: 1-6 (Wheat, Carrot, Potato, Tomato, Corn, Pumpkin) and 11-14 (Berry, Herbs, Magic Mushroom, Enchanted Flower)
  const cropIds = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14];
  return cropIds.includes(itemId);
};

export const isOre = (itemId: number): boolean => {
  return itemId >= 20 && itemId <= 29;
};

export const isProductionItem = (itemId: number): boolean => {
  // Production items: 7-10 (Minor Healing Potion, Bread, Magic Essence, Enchanted Seeds) and 15-19 (Herbal Tea, Magic Potion, Fruit Salad, Crystals)
  const productionIds = [7, 8, 9, 10, 15, 16, 17, 18, 19];
  return productionIds.includes(itemId);
};

export const isEquipment = (itemId: number): boolean => {
  return itemId >= 30 && itemId <= 39;
};

export const isFinishedProductionItem = (itemId: number): boolean => {
  // Production items (11-19) are finished items that can only be sold
  return itemId >= 11 && itemId <= 19;
};

// Helper functions for seed system
export const getSeedItemId = (cropId: number): number => {
  // Seeds use item_id 100 + cropId (where cropId maps to crop item_id 1-10)
  // cropId 1 (Wheat) -> seed item_id 101
  return 100 + cropId;
};

export const getCropIdFromSeed = (seedItemId: number): number => {
  // Convert seed item_id back to crop item_id
  return seedItemId - 100;
};

// Helper functions for leveled animals (item_id format: 1000 + (animal_type_id * 100) + level)
export const isLeveledAnimal = (itemId: number): boolean => {
  return itemId >= 1000;
};

export const getAnimalLevelFromItemId = (itemId: number): number | null => {
  if (!isLeveledAnimal(itemId)) {
    return null;
  }
  const level = (itemId - 1000) % 100;
  if (level < 0 || level > 10) {
    return null;
  }
  return level;
};

export const getAnimalTypeIdFromItemId = (itemId: number): number | null => {
  if (itemId >= 1000) {
    // New format: 1000 + (animal_type_id * 100) + level
    return Math.floor((itemId - 1000) / 100);
  } else if (itemId >= 30 && itemId < 100) {
    // Old format: 30 + animal_type_id (level 0)
    return itemId - 30;
  }
  return null;
};

// Animal type names mapping (should match animal_types table)
const animalTypeNames: Record<number, string> = {
  1: 'Chicken',
  2: 'Cow',
  3: 'Pig',
  4: 'Sheep',
  5: 'Unicorn',
  6: 'Phoenix',
  7: 'Dragon',
  8: 'Spirit Wolf',
  9: 'Ancient Guardian',
};

// Animal type icons mapping (should match animal_types table)
const animalTypeIcons: Record<number, string> = {
  1: '🐔',
  2: '🐄',
  3: '🐷',
  4: '🐑',
  5: '🦄',
  6: '🔥',
  7: '🐉',
  8: '🐺',
  9: '🛡️',
};

export const getAnimalName = (animalTypeId: number): string => {
  return animalTypeNames[animalTypeId] || `Animal ${animalTypeId}`;
};

export const getAnimalIcon = (animalTypeId: number): string => {
  return animalTypeIcons[animalTypeId] || '🐾';
};

// Enhanced getItemName to handle leveled animals
export const getItemNameWithLevel = (itemId: number): string => {
  const animalTypeId = getAnimalTypeIdFromItemId(itemId);
  if (animalTypeId !== null) {
    const level = getAnimalLevelFromItemId(itemId);
    const animalName = getAnimalName(animalTypeId);
    if (level !== null && level > 0) {
      return `${animalName} +${level}`;
    }
    return animalName;
  }
  return getItemName(itemId);
};

// Enhanced getItemIcon to handle leveled animals
export const getItemIconWithAnimal = (itemId: number): string => {
  const animalTypeId = getAnimalTypeIdFromItemId(itemId);
  if (animalTypeId !== null) {
    return getAnimalIcon(animalTypeId);
  }
  return getItemIcon(itemId);
};

// Armory type name formatting - converts technical names to user-friendly display names
export const getArmoryTypeName = (armoryType: string): string => {
  const armoryTypeNames: Record<string, string> = {
    basic_forge: 'Basic Forge',
    // Add more armory types here as they're added to the game
  };
  
  return armoryTypeNames[armoryType] || armoryType
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

