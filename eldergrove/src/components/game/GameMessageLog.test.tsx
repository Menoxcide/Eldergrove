import React from 'react';
import { render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import GameMessageLog from './GameMessageLog';

// Mock the stores
let mockUseGameMessageStore: jest.MockedFunction<any>;

jest.mock('@/stores/useGameMessageStore', () => ({
  useGameMessageStore: () => mockUseGameMessageStore(),
}));

beforeEach(() => {
  mockUseGameMessageStore = jest.fn();
});

// Mock scrollIntoView to prevent DOM errors in tests
Object.defineProperty(HTMLElement.prototype, 'scrollIntoView', {
  writable: true,
  value: jest.fn(),
});

// Mock item utilities
jest.mock('@/lib/itemUtils', () => ({
  getItemIcon: jest.fn((id: number) => {
    const icons: Record<number, string> = {
      1: '🌾', // wheat
      2: '🥕', // carrot
      8: '🍞', // bread
      30: '⚔️', // iron_sword
      113: '🐔', // chicken
    };
    return icons[id] || '❓';
  }),
  getItemName: jest.fn((id: number) => {
    const names: Record<number, string> = {
      1: 'Wheat',
      2: 'Carrot',
      8: 'Bread',
      30: 'Iron Sword',
      113: 'Chicken',
    };
    return names[id] || `Item ${id}`;
  }),
  getItemNameWithLevel: jest.fn((id: number) => {
    const names: Record<number, string> = {
      1: 'Wheat',
      2: 'Carrot',
      8: 'Bread',
      30: 'Iron Sword',
      113: 'Chicken +1',
    };
    return names[id] || `Item ${id}`;
  }),
  getItemIconWithAnimal: jest.fn((id: number) => {
    const icons: Record<number, string> = {
      1: '🌾',
      2: '🥕',
      8: '🍞',
      30: '⚔️',
      113: '🐔',
    };
    return icons[id] || '❓';
  }),
}));

describe('GameMessageLog Component - Item Name Display', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Factory Collection Messages (Legacy Format)', () => {
    test('displays correct item names for factory collection with bread output', () => {
      const mockMessages = [
        {
          id: '1',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'bread': 2 }, // Legacy format using item names
        },
      ];

      // Mock the store to return our test messages
      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should display "2 Bread" instead of "2 bread"
      expect(screen.getByText('2 Bread')).toBeInTheDocument();
      expect(screen.getByText('🍞')).toBeInTheDocument();
    });

    test('displays correct item names for factory collection with multiple crops', () => {
      const mockMessages = [
        {
          id: '2',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'wheat': 5, 'carrot': 3 }, // Legacy format
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('5 Wheat')).toBeInTheDocument();
      expect(screen.getByText('3 Carrot')).toBeInTheDocument();
      expect(screen.getAllByText('🌾')).toHaveLength(1);
      expect(screen.getAllByText('🥕')).toHaveLength(1);
    });

    test('handles unknown item names gracefully', () => {
      const mockMessages = [
        {
          id: '3',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'unknown_item': 1 }, // Item not in mapping
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should not display unknown items since extractItemIdFromKey returns null
      expect(screen.queryByText('unknown_item')).not.toBeInTheDocument();
    });
  });

  describe('Armory Collection Messages (Legacy Format)', () => {
    test('displays correct item names for armory collection with equipment', () => {
      const mockMessages = [
        {
          id: '4',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'iron_sword': 1 }, // Legacy format
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('1 Iron Sword')).toBeInTheDocument();
      expect(screen.getByText('⚔️')).toBeInTheDocument();
    });
  });

  describe('Zoo Collection Messages (New Format)', () => {
    test('displays correct item names for zoo production collection using itemIds', () => {
      const mockMessages = [
        {
          id: '5',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          itemIds: { 113: 2 }, // New format using item IDs
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('2 Chicken +1')).toBeInTheDocument();
      expect(screen.getByText('🐔')).toBeInTheDocument();
    });

    test('displays correct item names for zoo breeding collection using itemIds', () => {
      const mockMessages = [
        {
          id: '6',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          itemIds: { 113: 1 }, // New format
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('1 Chicken +1')).toBeInTheDocument();
    });
  });

  describe('Legacy Message Format Compatibility', () => {
    test('handles "item_XXX" format correctly', () => {
      const mockMessages = [
        {
          id: '7',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'item_1': 3 }, // Legacy "item_XXX" format
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('3 Wheat')).toBeInTheDocument();
    });

    test('prefers itemIds over items when both are present for the same item', () => {
      const mockMessages = [
        {
          id: '8',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          itemIds: { 1: 2 }, // Preferred format - wheat
          items: { 'wheat': 5 }, // Legacy format - should be ignored since same item
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should show only the itemIds version (2 Wheat) and not the items version (5 Wheat)
      expect(screen.getByText('2 Wheat')).toBeInTheDocument();
      expect(screen.queryByText('5 Wheat')).not.toBeInTheDocument();
    });
  });

  describe('Edge Cases and Error Conditions', () => {
    test('handles empty collection messages gracefully', () => {
      const mockMessages = [
        {
          id: '9',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: {},
          itemIds: {},
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should render the message but no items section
      expect(screen.getByText('Collection Complete!')).toBeInTheDocument();
      expect(screen.queryByText('Items Collected:')).not.toBeInTheDocument();
    });

    test('handles invalid item IDs gracefully', () => {
      const mockMessages = [
        {
          id: '10',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          itemIds: { 99999: 1 }, // Invalid item ID
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should display fallback name
      expect(screen.getByText('1 Item 99999')).toBeInTheDocument();
    });

    test('handles mixed valid and invalid items', () => {
      const mockMessages = [
        {
          id: '11',
          type: 'collection' as const,
          content: 'Collection Complete!',
          timestamp: Date.now(),
          items: { 'bread': 2, 'invalid_item': 1 }, // One valid, one invalid
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      // Should show only the valid item
      expect(screen.getByText('2 Bread')).toBeInTheDocument();
      expect(screen.queryByText('invalid_item')).not.toBeInTheDocument();
    });

    test('handles non-collection message types without items', () => {
      const mockMessages = [
        {
          id: '12',
          type: 'success' as const,
          content: 'Task completed successfully!',
          timestamp: Date.now(),
        },
      ];

      mockUseGameMessageStore.mockReturnValue({
        messages: mockMessages,
        removeMessage: jest.fn(),
        clearMessages: jest.fn(),
      });

      render(<GameMessageLog />);

      expect(screen.getByText('Task completed successfully!')).toBeInTheDocument();
      // Should not have collection-specific elements
      expect(screen.queryByText('Items Collected:')).not.toBeInTheDocument();
    });
  });

  describe('Item Mapping Coverage', () => {
    test('covers all mapped item names from itemNameToId', () => {
      // Test a few key mappings to ensure they work
      const testCases = [
        { name: 'wheat', expectedId: 1, expectedName: 'Wheat' },
        { name: 'iron_sword', expectedId: 30, expectedName: 'Iron Sword' },
        { name: 'bread', expectedId: 8, expectedName: 'Bread' },
      ];

      testCases.forEach(({ name, expectedId, expectedName }) => {
        const mockMessages = [
          {
            id: `test-${name}`,
            type: 'collection' as const,
            content: 'Test Collection',
            timestamp: Date.now(),
            items: { [name]: 1 },
          },
        ];

        mockUseGameMessageStore.mockReturnValue({
          messages: mockMessages,
          removeMessage: jest.fn(),
          clearMessages: jest.fn(),
        });

        const { rerender } = render(<GameMessageLog />);

        expect(screen.getByText(`1 ${expectedName}`)).toBeInTheDocument();

        // Cleanup for next test
        jest.clearAllMocks();
      });
    });
  });
});