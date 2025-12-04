// Error parsing and formatting utilities for user-friendly error messages

import { getItemName, getItemIcon, getItemNameWithLevel } from './itemUtils';
import { getItemIdFromName } from './itemMappings';

export interface ParsedError {
  type: 'resource' | 'slot' | 'seed' | 'population' | 'grid' | 'validation' | 'other';
  title: string;
  message: string;
  details?: {
    resource?: string;
    required?: number;
    available?: number;
    itemId?: number;
    itemName?: string;
    slot?: number;
    maxSlots?: number;
    currentSlots?: number;
    factoryType?: string;
    cropId?: number;
    cropName?: string;
    seedItemId?: number;
    gridX?: number;
    gridY?: number;
  };
  suggestion?: string;
  icon?: string;
}

/**
 * Extract error message from various error types, including Supabase errors
 */
function extractErrorMessage(error: unknown): string {
  // Handle Supabase PostgREST errors
  if (error && typeof error === 'object') {
    const errorObj = error as Record<string, unknown>;
    
    // Supabase errors have a message property
    if (errorObj.message && typeof errorObj.message === 'string') {
      return errorObj.message;
    }
    
    // Some Supabase errors have error.message nested
    if (errorObj.error && typeof errorObj.error === 'object') {
      const nestedError = errorObj.error as Record<string, unknown>;
      if (nestedError.message && typeof nestedError.message === 'string') {
        return nestedError.message;
      }
    }
  }
  
  // Standard Error objects
  if (error instanceof Error) {
    return error.message;
  }
  
  // Fallback to string conversion
  return String(error);
}

/**
 * Parse database error messages into structured error information
 */
export function parseError(error: unknown): ParsedError {
  const errorMessage = extractErrorMessage(error);
  
  // Insufficient crystals
  const crystalMatch = errorMessage.match(/Insufficient crystals: required (\d+), available (\d+)/i);
  if (crystalMatch) {
    const required = parseInt(crystalMatch[1]);
    const available = parseInt(crystalMatch[2]);
    const needed = required - available;
    return {
      type: 'resource',
      title: 'Not Enough Crystals',
      message: `You need ${needed.toLocaleString()} more crystals to complete this action.`,
      details: {
        resource: 'crystals',
        required,
        available,
      },
      suggestion: 'Earn more crystals by completing orders, harvesting crops, or selling items.',
      icon: '💎',
    };
  }

  // Insufficient aether
  const aetherMatch = errorMessage.match(/Insufficient aether: required (\d+), available (\d+)/i);
  if (aetherMatch) {
    const required = parseInt(aetherMatch[1]);
    const available = parseInt(aetherMatch[2]);
    const needed = required - available;
    return {
      type: 'resource',
      title: 'Not Enough Aether',
      message: `You need ${needed.toLocaleString()} more aether to complete this action.`,
      details: {
        resource: 'aether',
        required,
        available,
      },
      suggestion: 'Complete quests and achievements to earn aether.',
      icon: '✨',
    };
  }

  // Insufficient items/resources (generic)
  const resourceMatch = errorMessage.match(/Insufficient "([^"]+)": required (\d+), available (\d+)/i);
  if (resourceMatch) {
    const resourceName = resourceMatch[1];
    const required = parseInt(resourceMatch[2]);
    const available = parseInt(resourceMatch[3]);
    
    // Try to map resource name to item ID
    const itemId = getItemIdFromResourceName(resourceName);
    const itemName = itemId ? getItemNameWithLevel(itemId) : resourceName;
    const icon = itemId ? getItemIcon(itemId) : '📦';
    
    return {
      type: 'resource',
      title: `Not Enough ${itemName}`,
      message: `You need ${(required - available).toLocaleString()} more ${itemName} to complete this action.`,
      details: {
        resource: resourceName,
        required,
        available,
        itemId,
        itemName,
      },
      suggestion: `Gather more ${itemName} by harvesting crops, completing production, or purchasing from the shop.`,
      icon,
    };
  }

  // Insufficient items from inventory (with item_id)
  const itemMatch = errorMessage.match(/Insufficient.*item_id (\d+).*required (\d+).*available (\d+)/i);
  if (itemMatch) {
    const itemId = parseInt(itemMatch[1]);
    const required = parseInt(itemMatch[2]);
    const available = parseInt(itemMatch[3]);
    const itemName = getItemNameWithLevel(itemId);
    const icon = getItemIcon(itemId);
    
    return {
      type: 'resource',
      title: `Not Enough ${itemName}`,
      message: `You need ${(required - available).toLocaleString()} more ${itemName} to complete this action.`,
      details: {
        required,
        available,
        itemId,
        itemName,
      },
      suggestion: `Gather more ${itemName} by harvesting crops, completing production, or purchasing from the shop.`,
      icon,
    };
  }

  // Factory slots full
  const factorySlotMatch = errorMessage.match(/Factory "([^"]+)" queue is full \(max (\d+) slots?\)/i);
  if (factorySlotMatch) {
    const factoryType = factorySlotMatch[1];
    const maxSlots = parseInt(factorySlotMatch[2]);
    return {
      type: 'slot',
      title: 'Factory Queue Full',
      message: `Your ${factoryType} factory has reached its maximum capacity of ${maxSlots} slots.`,
      details: {
        factoryType,
        maxSlots,
      },
      suggestion: 'Wait for current production to finish, or purchase additional factory slots to increase capacity.',
      icon: '🏭',
    };
  }

  // Factory slots full with upgrade suggestion
  const factorySlotUpgradeMatch = errorMessage.match(/Factory "([^"]+)" queue is full \(max (\d+) slots?\)\. Purchase more slots to increase capacity\./i);
  if (factorySlotUpgradeMatch) {
    const factoryType = factorySlotUpgradeMatch[1];
    const maxSlots = parseInt(factorySlotUpgradeMatch[2]);
    return {
      type: 'slot',
      title: 'Factory Queue Full',
      message: `Your ${factoryType} factory has reached its maximum capacity of ${maxSlots} slots.`,
      details: {
        factoryType,
        maxSlots,
      },
      suggestion: 'Purchase additional factory slots from the upgrade menu to increase capacity.',
      icon: '🏭',
    };
  }

  // Zoo enclosure slot occupied
  const zooSlotMatch = errorMessage.match(/Slot (\d+) is already occupied/i);
  if (zooSlotMatch) {
    const slot = parseInt(zooSlotMatch[1]);
    return {
      type: 'slot',
      title: 'Enclosure Slot Occupied',
      message: `Slot ${slot} in this enclosure is already occupied by another animal.`,
      details: {
        slot,
      },
      suggestion: 'Select an empty slot or remove the current animal first.',
      icon: '🦁',
    };
  }

  // No seed available
  const seedMatch = errorMessage.match(/You do not have a seed for this crop\. Seed item_id (\d+) required\./i);
  if (seedMatch) {
    const seedItemId = parseInt(seedMatch[1]);
    const cropId = seedItemId - 100; // Seeds are 100 + crop_id
    const cropName = getItemNameWithLevel(cropId);
    const seedName = getItemNameWithLevel(seedItemId);
    return {
      type: 'seed',
      title: 'No Seed Available',
      message: `You don't have a ${seedName} to plant ${cropName}.`,
      details: {
        seedItemId,
        cropId,
        cropName,
        itemName: seedName,
      },
      suggestion: `Purchase ${seedName} from the seed shop to plant ${cropName}.`,
      icon: '🌱',
    };
  }

  // Seed purchase failed
  const seedPurchaseMatch = errorMessage.match(/Seed for crop_id (\d+) is not available in the shop/i);
  if (seedPurchaseMatch) {
    const cropId = parseInt(seedPurchaseMatch[1]);
    const cropName = getItemNameWithLevel(cropId);
    return {
      type: 'seed',
      title: 'Seed Not Available',
      message: `The seed for ${cropName} is not currently available in the shop.`,
      details: {
        cropId,
        cropName,
      },
      suggestion: 'Check back later or unlock this seed through gameplay.',
      icon: '🌱',
    };
  }

  // Population requirement not met
  const populationMatch = errorMessage.match(/Insufficient population: required (\d+), available (\d+)/i);
  if (populationMatch) {
    const required = parseInt(populationMatch[1]);
    const available = parseInt(populationMatch[2]);
    const needed = required - available;
    return {
      type: 'population',
      title: 'Population Requirement Not Met',
      message: `You need ${needed.toLocaleString()} more population to build this structure.`,
      details: {
        required,
        available,
      },
      suggestion: 'Build houses and decorations to increase your population.',
      icon: '🏘️',
    };
  }

  // Grid cell occupied
  const gridMatch = errorMessage.match(/Grid cell \((\d+), (\d+)\) is already occupied/i);
  if (gridMatch) {
    const gridX = parseInt(gridMatch[1]);
    const gridY = parseInt(gridMatch[2]);
    return {
      type: 'grid',
      title: 'Location Occupied',
      message: `The location at (${gridX}, ${gridY}) is already occupied by another building.`,
      details: {
        gridX,
        gridY,
      },
      suggestion: 'Select a different location for your building.',
      icon: '🏗️',
    };
  }

  // Plot already planted
  const plotPlantedMatch = errorMessage.match(/plot.*already.*planted|plot.*not.*empty/i);
  if (plotPlantedMatch) {
    return {
      type: 'validation',
      title: 'Plot Already Planted',
      message: 'This plot already has a crop growing.',
      suggestion: 'Wait for the current crop to finish growing, or harvest it first.',
      icon: '🌾',
    };
  }

  // Crop not ready
  const cropNotReadyMatch = errorMessage.match(/crop.*not.*ready|not.*ready.*harvest/i);
  if (cropNotReadyMatch) {
    return {
      type: 'validation',
      title: 'Crop Not Ready',
      message: 'This crop is not ready to harvest yet.',
      suggestion: 'Wait for the crop to finish growing.',
      icon: '🌾',
    };
  }

  // Inventory storage full
  const storageMatch = errorMessage.match(/storage.*full|inventory.*full|capacity.*exceeded/i);
  if (storageMatch) {
    return {
      type: 'slot',
      title: 'Storage Full',
      message: 'Your inventory storage is full.',
      suggestion: 'Sell items or upgrade your warehouse to increase storage capacity.',
      icon: '📦',
    };
  }

  // Animal not in inventory
  const animalInventoryMatch = errorMessage.match(/You do not have this animal in your inventory/i);
  if (animalInventoryMatch) {
    return {
      type: 'resource',
      title: 'Animal Not Available',
      message: 'You do not have this animal in your inventory.',
      suggestion: 'Purchase animals from the shop or breed them in your zoo.',
      icon: '🦁',
    };
  }

  // Default fallback
  return {
    type: 'other',
    title: 'Action Failed',
    message: errorMessage,
    icon: '⚠️',
  };
}

/**
 * Map resource names to item IDs
 */
function getItemIdFromResourceName(resourceName: string): number | undefined {
  return getItemIdFromName(resourceName);
}

/**
 * Format error for display in dialog
 */
export function formatErrorForDialog(parsedError: ParsedError): string {
  let message = `${parsedError.icon || '⚠️'} ${parsedError.title}\n\n${parsedError.message}`;
  
  if (parsedError.details) {
    if (parsedError.details.required !== undefined && parsedError.details.available !== undefined) {
      message += `\n\nRequired: ${parsedError.details.required.toLocaleString()}`;
      message += `\nAvailable: ${parsedError.details.available.toLocaleString()}`;
    }
    if (parsedError.details.maxSlots !== undefined) {
      message += `\n\nSlots: ${parsedError.details.currentSlots || 0}/${parsedError.details.maxSlots}`;
    }
    if (parsedError.details.itemName) {
      message += `\n\nItem: ${parsedError.details.itemName}`;
    }
  }
  
  if (parsedError.suggestion) {
    message += `\n\n💡 ${parsedError.suggestion}`;
  }
  
  return message;
}

