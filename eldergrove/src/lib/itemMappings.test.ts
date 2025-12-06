import { ITEM_NAME_TO_ID, getItemIdFromName } from './itemMappings';
import {
  getItemName,
  getItemIcon,
  getItemCategory,
  isSeed,
  getSeedItemId,
  getCropIdFromSeed
} from './itemUtils';

describe('Item Mapping Fix Verification', () => {
  describe('getItemName() function for items 111-114', () => {
    test('should return correct names for Berry Seed (111)', () => {
      expect(getItemName(111)).toBe('Berry Seed');
    });

    test('should return correct names for Herbs Seed (112)', () => {
      expect(getItemName(112)).toBe('Herbs Seed');
    });

    test('should return correct names for Magic Mushroom Seed (113)', () => {
      expect(getItemName(113)).toBe('Magic Mushroom Seed');
    });

    test('should return correct names for Enchanted Flower Seed (114)', () => {
      expect(getItemName(114)).toBe('Enchanted Flower Seed');
    });
  });

  describe('getItemIcon() function for items 111-114', () => {
    test('should return correct icons for Berry Seed (111)', () => {
      expect(getItemIcon(111)).toBe('🍓');
    });

    test('should return correct icons for Herbs Seed (112)', () => {
      expect(getItemIcon(112)).toBe('🌿');
    });

    test('should return correct icons for Magic Mushroom Seed (113)', () => {
      expect(getItemIcon(113)).toBe('🍄');
    });

    test('should return correct icons for Enchanted Flower Seed (114)', () => {
      expect(getItemIcon(114)).toBe('🌸');
    });
  });

  describe('getItemCategory() function for items 111-114', () => {
    test('should categorize items 111-114 as seeds', () => {
      expect(getItemCategory(111)).toBe('seeds');
      expect(getItemCategory(112)).toBe('seeds');
      expect(getItemCategory(113)).toBe('seeds');
      expect(getItemCategory(114)).toBe('seeds');
    });

    test('should identify items 111-114 as seeds using isSeed()', () => {
      expect(isSeed(111)).toBe(true);
      expect(isSeed(112)).toBe(true);
      expect(isSeed(113)).toBe(true);
      expect(isSeed(114)).toBe(true);
    });
  });

  describe('name-to-ID lookups for new seed names', () => {
    test('should correctly map "berry_seed" to ID 111', () => {
      expect(ITEM_NAME_TO_ID['berry_seed']).toBe(111);
      expect(getItemIdFromName('berry_seed')).toBe(111);
      expect(getItemIdFromName('Berry Seed')).toBe(111); // normalized
    });

    test('should correctly map "herbs_seed" to ID 112', () => {
      expect(ITEM_NAME_TO_ID['herbs_seed']).toBe(112);
      expect(getItemIdFromName('herbs_seed')).toBe(112);
      expect(getItemIdFromName('Herbs Seed')).toBe(112); // normalized
    });

    test('should correctly map "magic_mushroom_seed" to ID 113', () => {
      expect(ITEM_NAME_TO_ID['magic_mushroom_seed']).toBe(113);
      expect(getItemIdFromName('magic_mushroom_seed')).toBe(113);
      expect(getItemIdFromName('Magic Mushroom Seed')).toBe(113); // normalized
    });

    test('should correctly map "enchanted_flower_seed" to ID 114', () => {
      expect(ITEM_NAME_TO_ID['enchanted_flower_seed']).toBe(114);
      expect(getItemIdFromName('enchanted_flower_seed')).toBe(114);
      expect(getItemIdFromName('Enchanted Flower Seed')).toBe(114); // normalized
    });
  });

  describe('Regression tests for existing items 101-110', () => {
    test('should maintain correct names for existing seeds 101-110', () => {
      expect(getItemName(101)).toBe('Wheat Seed');
      expect(getItemName(102)).toBe('Carrot Seed');
      expect(getItemName(103)).toBe('Potato Seed');
      expect(getItemName(104)).toBe('Tomato Seed');
      expect(getItemName(105)).toBe('Corn Seed');
      expect(getItemName(106)).toBe('Pumpkin Seed');
      expect(getItemName(107)).toBe('Berry Seed');
      expect(getItemName(108)).toBe('Herbs Seed');
      expect(getItemName(109)).toBe('Magic Mushroom Seed');
      expect(getItemName(110)).toBe('Enchanted Flower Seed');
    });

    test('should maintain correct icons for existing seeds 101-110', () => {
      expect(getItemIcon(101)).toBe('🌾');
      expect(getItemIcon(102)).toBe('🥕');
      expect(getItemIcon(103)).toBe('🥔');
      expect(getItemIcon(104)).toBe('🍅');
      expect(getItemIcon(105)).toBe('🌽');
      expect(getItemIcon(106)).toBe('🎃');
      expect(getItemIcon(107)).toBe('🍓');
      expect(getItemIcon(108)).toBe('🌿');
      expect(getItemIcon(109)).toBe('🍄');
      expect(getItemIcon(110)).toBe('🌸');
    });

    test('should maintain correct categories for existing seeds 101-110', () => {
      for (let i = 101; i <= 110; i++) {
        expect(getItemCategory(i)).toBe('seeds');
        expect(isSeed(i)).toBe(true);
      }
    });

    test('should maintain seed utility functions', () => {
      // Test getSeedItemId for crops 1-10
      expect(getSeedItemId(1)).toBe(101); // Wheat
      expect(getSeedItemId(2)).toBe(102); // Carrot
      expect(getSeedItemId(11)).toBe(111); // Berry (crop 11)
      expect(getSeedItemId(12)).toBe(112); // Herbs (crop 12)
      expect(getSeedItemId(13)).toBe(113); // Magic Mushroom (crop 13)
      expect(getSeedItemId(14)).toBe(114); // Enchanted Flower (crop 14)

      // Test getCropIdFromSeed
      expect(getCropIdFromSeed(101)).toBe(1); // Wheat seed -> crop 1
      expect(getCropIdFromSeed(111)).toBe(11); // Berry seed -> crop 11
      expect(getCropIdFromSeed(112)).toBe(12); // Herbs seed -> crop 12
      expect(getCropIdFromSeed(113)).toBe(13); // Magic Mushroom seed -> crop 13
      expect(getCropIdFromSeed(114)).toBe(14); // Enchanted Flower seed -> crop 14
    });
  });

  describe('Edge cases and error handling', () => {
    test('should handle unknown item IDs gracefully', () => {
      expect(getItemName(999)).toBe('Item 999');
      expect(getItemIcon(999)).toBe('📦');
      expect(getItemCategory(999)).toBe('other');
    });

    test('should handle non-existent item names', () => {
      expect(getItemIdFromName('nonexistent_item')).toBeUndefined();
      expect(getItemIdFromName('')).toBeUndefined();
    });

    test('should handle normalization edge cases', () => {
      expect(getItemIdFromName('BERRY SEED')).toBe(111);
      expect(getItemIdFromName('berry   seed')).toBe(111);
      expect(getItemIdFromName('Berry_Seed')).toBe(111);
    });
  });
});