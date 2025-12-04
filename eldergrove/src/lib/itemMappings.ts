/**
 * Centralized mapping of item names to their corresponding item IDs.
 * This eliminates duplication across multiple files and ensures consistency.
 */
export const ITEM_NAME_TO_ID: Record<string, number> = {
  wheat: 1,
  carrot: 2,
  potato: 3,
  tomato: 4,
  corn: 5,
  pumpkin: 6,
  bread: 8,
  berry: 11,
  herbs: 12,
  magic_mushroom: 13,
  enchanted_flower: 14,
};

/**
 * Get item ID from item name, with optional normalization.
 * @param itemName - The name of the item
 * @param normalize - Whether to normalize the name (default: true)
 * @returns The item ID or undefined if not found
 */
export function getItemIdFromName(itemName: string, normalize: boolean = true): number | undefined {
  const key = normalize ? itemName.toLowerCase().replace(/\s+/g, '_') : itemName;
  return ITEM_NAME_TO_ID[key];
}