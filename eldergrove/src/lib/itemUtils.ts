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
    111: '🍓',  // Berry Seed
    112: '🌿',  // Herbs Seed
    113: '🍄',  // Magic Mushroom Seed
    114: '🌸',  // Enchanted Flower Seed
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
    111: 'Berry Seed',
    112: 'Herbs Seed',
    113: 'Magic Mushroom Seed',
    114: 'Enchanted Flower Seed',
  };
  return itemNames[itemId] || `Item ${itemId}`;
};

export type ItemCategory = 'seeds' | 'crops' | 'production' | 'ore' | 'equipment' | 'other';

export const getItemCategory = (itemId: number): ItemCategory => {
  if ((itemId >= 100 && itemId <= 110) || (itemId >= 111 && itemId <= 114)) {
    return 'seeds';
  }

  const cropIds = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14];
  if (cropIds.includes(itemId)) {
    return 'crops';
  }

  const productionIds = [7, 8, 9, 10, 15, 16, 17, 18, 19];
  if (productionIds.includes(itemId)) {
    return 'production';
  }

  if (itemId >= 20 && itemId <= 29) {
    return 'ore';
  }
  if (itemId >= 30 && itemId <= 39) {
    return 'equipment';
  }
  return 'other';
};

export const getCategoryName = (category: ItemCategory): string => {
  switch (category) {
    case 'seeds': return 'Seeds';
    case 'crops': return 'Crops';
    case 'production': return 'Production';
    case 'ore': return 'Ore';
    case 'equipment': return 'Equipment';
    case 'other': return 'Other';
  }
};

export const isSeed = (itemId: number): boolean => {
  return itemId >= 100 && itemId <= 114;
};

export const isCrop = (itemId: number): boolean => {
  const cropIds = [1, 2, 3, 4, 5, 6, 11, 12, 13, 14];
  return cropIds.includes(itemId);
};

export const isOre = (itemId: number): boolean => {
  return itemId >= 20 && itemId <= 29;
};

export const isProductionItem = (itemId: number): boolean => {
  const productionIds = [7, 8, 9, 10, 15, 16, 17, 18, 19];
  return productionIds.includes(itemId);
};

export const isEquipment = (itemId: number): boolean => {
  return itemId >= 30 && itemId <= 39;
};

export const isFinishedProductionItem = (itemId: number): boolean => {
  return (itemId >= 7 && itemId <= 10) || (itemId >= 15 && itemId <= 19);
};

export const getSeedItemId = (cropId: number): number => {
  return 100 + cropId;
};

export const getCropIdFromSeed = (seedItemId: number): number => {
  return seedItemId - 100;
};

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
    return Math.floor((itemId - 1000) / 100);
  } else if (itemId >= 30 && itemId < 100) {
    return itemId - 30;
  }
  return null;
};

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

export const getItemIconWithAnimal = (itemId: number): string => {
  const animalTypeId = getAnimalTypeIdFromItemId(itemId);
  if (animalTypeId !== null) {
    return getAnimalIcon(animalTypeId);
  }
  return getItemIcon(itemId);
};

export const getArmoryTypeName = (armoryType: string): string => {
  const armoryTypeNames: Record<string, string> = {
    basic_forge: 'Basic Forge',
  };
  
  return armoryTypeNames[armoryType] || armoryType
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

