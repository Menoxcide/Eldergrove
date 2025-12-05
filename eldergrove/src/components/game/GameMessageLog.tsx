'use client';

import { useEffect, useRef, useState } from 'react';
import { useGameMessageStore, type GameMessage } from '@/stores/useGameMessageStore';
import { getItemIcon, getItemName, getItemNameWithLevel, getItemIconWithAnimal } from '@/lib/itemUtils';

const GameMessageLog = () => {
  const { messages, removeMessage, clearMessages } = useGameMessageStore();
  const [isMinimized, setIsMinimized] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (!isMinimized && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isMinimized]);

  const formatTime = (timestamp: number): string => {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', { 
      hour: '2-digit', 
      minute: '2-digit',
      hour12: false 
    });
  };

  const getMessageIcon = (type: GameMessage['type']): string => {
    switch (type) {
      case 'success':
        return '✅';
      case 'error':
        return '⚠️';
      case 'info':
        return 'ℹ️';
      case 'collection':
        return '📦';
      default:
        return '•';
    }
  };

  const getMessageColor = (type: GameMessage['type']): string => {
    switch (type) {
      case 'success':
        return 'text-green-400';
      case 'error':
        return 'text-red-400';
      case 'info':
        return 'text-blue-400';
      case 'collection':
        return 'text-emerald-400';
      default:
        return 'text-slate-300';
    }
  };

  const getMessageBgColor = (type: GameMessage['type']): string => {
    switch (type) {
      case 'success':
        return 'bg-green-900/20 border-green-700/50';
      case 'error':
        return 'bg-red-900/20 border-red-700/50';
      case 'info':
        return 'bg-blue-900/20 border-blue-700/50';
      case 'collection':
        return 'bg-emerald-900/20 border-emerald-700/50';
      default:
        return 'bg-slate-800/40 border-slate-700/50';
    }
  };

  // Map recipe output names to item IDs for display (legacy support)
  const itemNameToId: Record<string, number> = {
    'wheat': 1,
    'carrot': 2,
    'potato': 3,
    'tomato': 4,
    'corn': 5,
    'pumpkin': 6,
    'berry': 11,
    'herbs': 12,
    'magic_mushroom': 13,
    'enchanted_flower': 14,
    'bread': 8,
    'vegetable_stew': 12,
    'corn_bread': 13,
    'pumpkin_pie': 14,
    'herbal_tea': 15,
    'magic_potion': 16,
    'fruit_salad': 17,
    // Seeds (100-110)
    'wheat_seed': 101,
    'carrot_seed': 102,
    'potato_seed': 103,
    'tomato_seed': 104,
    'corn_seed': 105,
    'pumpkin_seed': 106,
    'berry_seed': 107,
    'herbs_seed': 108,
    'magic_mushroom_seed': 109,
    'enchanted_flower_seed': 110,
    // Equipment (30-39)
    'iron_sword': 30,
    'steel_blade': 31,
    'diamond_armor': 32,
    'mithril_sword': 33,
    'aether_blade': 34,
    'dragon_scale_armor': 35,
    'ancient_relic_weapon': 36,
  };

  // Helper function to extract item_id from a key (handles "item_113" format)
  const extractItemIdFromKey = (key: string): number | null => {
    // Try direct mapping first
    const directId = itemNameToId[key.toLowerCase()];
    if (directId) return directId;

    // Try to extract from "item_XXX" format
    const itemMatch = key.match(/^item[_\s]?(\d+)$/i);
    if (itemMatch) {
      const id = parseInt(itemMatch[1], 10);
      if (!isNaN(id)) return id;
    }

    return null;
  };

  const renderMessage = (message: GameMessage) => {
    // Prefer itemIds (item_id -> quantity) over items (name -> quantity)
    const itemIdEntries = message.itemIds ? Object.entries(message.itemIds).map(([id, qty]) => [parseInt(id, 10), qty] as [number, number]) : [];
    const itemNameEntries = message.items ? Object.entries(message.items) : [];

    // Combine both formats, preferring itemIds
    const allItems: Array<{ itemId: number; quantity: number }> = [];

    // Add items from itemIds (preferred format)
    itemIdEntries.forEach(([itemId, quantity]) => {
      allItems.push({ itemId, quantity });
    });

    // Add items from items (legacy format), but skip if already in itemIds
    itemNameEntries.forEach(([itemName, quantity]) => {
      const itemId = extractItemIdFromKey(itemName);
      if (itemId && !allItems.some(item => item.itemId === itemId)) {
        allItems.push({ itemId, quantity });
      }
    });

    return (
      <div
        key={message.id}
        className={`p-3 rounded-lg border ${getMessageBgColor(message.type)} transition-all duration-200 hover:bg-opacity-30`}
      >
        <div className="flex items-start gap-2">
          <span className="text-lg flex-shrink-0">{getMessageIcon(message.type)}</span>
          <div className="flex-1 min-w-0">
            <div className={`font-semibold ${getMessageColor(message.type)} mb-1`}>
              {message.content}
            </div>
            
            {/* Collection details */}
            {message.type === 'collection' && (
              <div className="space-y-2 mt-2">
                {/* Items Collected */}
                {allItems.length > 0 && (
                  <div className="space-y-1">
                    <div className="text-emerald-200 text-xs font-semibold uppercase tracking-wide">
                      Items Collected:
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {allItems.map(({ itemId, quantity }) => (
                        <div
                          key={itemId}
                          className="flex items-center gap-2 px-2 py-1 bg-emerald-950/50 rounded border border-emerald-700/50 text-sm"
                        >
                          <span className="text-lg">{getItemIconWithAnimal(itemId)}</span>
                          <span className="text-white font-semibold">
                            {quantity.toLocaleString()} {getItemNameWithLevel(itemId)}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Crystals Awarded */}
                {message.crystals && message.crystals > 0 && (
                  <div className="flex items-center gap-2 px-2 py-1 bg-yellow-900/50 rounded border border-yellow-700/50 text-sm">
                    <span className="text-lg">💎</span>
                    <span className="text-yellow-200 font-semibold">
                      +{message.crystals.toLocaleString()} Crystals
                    </span>
                  </div>
                )}

                {/* XP Gained */}
                {message.xp && message.xp > 0 && (
                  <div className="flex items-center gap-2 px-2 py-1 bg-blue-900/50 rounded border border-blue-700/50 text-sm">
                    <span className="text-lg">⭐</span>
                    <span className="text-blue-200 font-semibold">
                      +{message.xp.toLocaleString()} XP
                    </span>
                  </div>
                )}
              </div>
            )}
            
            <div className="text-slate-400 text-xs mt-1">
              {formatTime(message.timestamp)}
            </div>
          </div>
          <button
            onClick={() => removeMessage(message.id)}
            className="text-slate-400 hover:text-slate-200 transition-colors flex-shrink-0"
            aria-label="Remove message"
          >
            ✕
          </button>
        </div>
      </div>
    );
  };

  if (isMinimized) {
    return (
      <div className="fixed bottom-24 right-4 z-50">
        <button
          onClick={() => setIsMinimized(false)}
          className="bg-slate-800/90 backdrop-blur-md rounded-lg p-3 shadow-lg border border-slate-700/50 hover:bg-slate-700/90 transition-colors"
          aria-label="Show messages"
        >
          <span className="text-xl">💬</span>
          {messages.length > 0 && (
            <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
              {messages.length > 9 ? '9+' : messages.length}
            </span>
          )}
        </button>
      </div>
    );
  }

  return (
    <div
      className={`fixed bottom-24 right-4 z-50 bg-slate-900/95 backdrop-blur-md rounded-xl shadow-2xl border border-slate-700/50 transition-all duration-300 ${
        isExpanded ? 'w-96 h-[600px]' : 'w-80 h-96'
      }`}
    >
      {/* Header */}
      <div className="flex items-center justify-between p-3 border-b border-slate-700/50">
        <h3 className="text-white font-bold text-lg">Game Messages</h3>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsExpanded(!isExpanded)}
            className="text-slate-400 hover:text-slate-200 transition-colors"
            aria-label={isExpanded ? 'Collapse' : 'Expand'}
          >
            {isExpanded ? '⊟' : '⊞'}
          </button>
          {messages.length > 0 && (
            <button
              onClick={clearMessages}
              className="text-slate-400 hover:text-red-400 transition-colors text-sm"
              aria-label="Clear all messages"
            >
              Clear
            </button>
          )}
          <button
            onClick={() => setIsMinimized(true)}
            className="text-slate-400 hover:text-slate-200 transition-colors"
            aria-label="Minimize"
          >
            −
          </button>
        </div>
      </div>

      {/* Messages Container */}
      <div
        ref={scrollContainerRef}
        className="flex-1 overflow-y-auto p-3 space-y-2 scrollbar-thin scrollbar-thumb-slate-600 scrollbar-track-slate-900/50"
        style={{ height: isExpanded ? 'calc(600px - 60px)' : 'calc(384px - 60px)' }}
      >
        {messages.length === 0 ? (
          <div className="text-slate-400 text-center py-8 italic">
            No messages yet
          </div>
        ) : (
          <>
            {messages.map(renderMessage)}
            <div ref={messagesEndRef} />
          </>
        )}
      </div>
    </div>
  );
};

export default GameMessageLog;

