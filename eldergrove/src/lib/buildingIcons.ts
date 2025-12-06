/**
 * Building icon and indicator mappings
 * Provides icons and visual indicators for each building type
 */

export interface BuildingIconConfig {
  icon: string; // Emoji or icon identifier
  categoryIcon: string; // Category indicator
  productionIcon?: string; // What it produces (for factories)
  functionIcon?: string; // What it does (for community buildings)
  color: string; // Category color
  badgeColor: string; // Badge background color
}

/**
 * Building icon configurations
 */
export const BUILDING_ICONS: Record<string, BuildingIconConfig> = {
  // Factory buildings - show production icons
  rune_bakery: {
    icon: '🍞',
    categoryIcon: '🏭',
    productionIcon: '🍞', // Produces bread and baked goods
    color: '#8B4513', // Brown
    badgeColor: '#A0522D', // Sienna
  },
  potion_workshop: {
    icon: '🧪',
    categoryIcon: '🏭',
    productionIcon: '🧪', // Produces potions
    color: '#9370DB', // Medium purple
    badgeColor: '#8A2BE2', // Blue violet
  },
  enchanting_lab: {
    icon: '✨',
    categoryIcon: '🏭',
    productionIcon: '✨', // Produces enchanted items
    color: '#4B0082', // Indigo
    badgeColor: '#6A0DAD', // Purple
  },
  kitchen: {
    icon: '👨‍🍳',
    categoryIcon: '🏭',
    productionIcon: '🍲', // Produces food/stew
    color: '#FF8C00', // Dark orange
    badgeColor: '#FF7F50', // Coral
  },
  
  // Community buildings - show function icons
  town_hall: {
    icon: '🏛️',
    categoryIcon: '🏘️',
    functionIcon: '👥', // Provides population
    color: '#1E90FF', // Dodger blue
    badgeColor: '#4169E1', // Royal blue
  },
  school: {
    icon: '🏫',
    categoryIcon: '🏘️',
    functionIcon: '📚', // Education/population
    color: '#DC143C', // Crimson
    badgeColor: '#B22222', // Fire brick
  },
  hospital: {
    icon: '🏥',
    categoryIcon: '🏘️',
    functionIcon: '💊', // Health/population
    color: '#FFFFFF', // White
    badgeColor: '#F0F0F0', // Light gray
  },
  cinema: {
    icon: '🎬',
    categoryIcon: '🏘️',
    functionIcon: '🎭', // Entertainment/population
    color: '#2F2F2F', // Dark gray
    badgeColor: '#1C1C1C', // Almost black
  },
  
  // Decorations
  fountain: {
    icon: '⛲',
    categoryIcon: '🎨',
    color: '#4682B4', // Steel blue
    badgeColor: '#5F9EA0', // Cadet blue
  },
  statue: {
    icon: '🗿',
    categoryIcon: '🎨',
    color: '#708090', // Slate gray
    badgeColor: '#778899', // Light slate gray
  },
  tree: {
    icon: '🌳',
    categoryIcon: '🎨',
    color: '#228B22', // Forest green
    badgeColor: '#32CD32', // Lime green
  },
};

/**
 * Get building icon configuration
 */
export function getBuildingIcon(buildingType: string): BuildingIconConfig | null {
  return BUILDING_ICONS[buildingType] || null;
}

/**
 * Get category display name
 */
export function getCategoryDisplayName(category: 'factory' | 'community' | 'decoration'): string {
  switch (category) {
    case 'factory':
      return 'Factory';
    case 'community':
      return 'Community';
    case 'decoration':
      return 'Decoration';
    default:
      return 'Building';
  }
}

/**
 * Get category color
 */
export function getCategoryColor(category: 'factory' | 'community' | 'decoration'): string {
  switch (category) {
    case 'factory':
      return '#8B4513'; // Brown
    case 'community':
      return '#2563EB'; // Blue
    case 'decoration':
      return '#84CC16'; // Green
    default:
      return '#666666';
  }
}

