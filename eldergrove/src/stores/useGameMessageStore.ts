import { create } from 'zustand';

export type MessageType = 'success' | 'error' | 'info' | 'collection';

export interface GameMessage {
  id: string;
  type: MessageType;
  content: string;
  timestamp: number;
  items?: Record<string, number>; // For collection messages: item name -> quantity (legacy format)
  itemIds?: Record<number, number>; // For collection messages: item_id -> quantity (preferred format)
  crystals?: number;
  xp?: number;
}

interface GameMessageState {
  messages: GameMessage[];
  maxMessages: number;
  addMessage: (type: MessageType, content: string, data?: { items?: Record<string, number>; itemIds?: Record<number, number>; crystals?: number; xp?: number }) => void;
  removeMessage: (id: string) => void;
  clearMessages: () => void;
}

export const useGameMessageStore = create<GameMessageState>((set, get) => ({
  messages: [],
  maxMessages: 100, // Keep last 100 messages
  
  addMessage: (type, content, data) => {
    const id = `msg-${Date.now()}-${Math.random()}`;
    const message: GameMessage = {
      id,
      type,
      content,
      timestamp: Date.now(),
      items: data?.items,
      itemIds: data?.itemIds,
      crystals: data?.crystals,
      xp: data?.xp,
    };
    
    set((state) => {
      const newMessages = [...state.messages, message];
      // Keep only the last maxMessages
      const trimmedMessages = newMessages.slice(-state.maxMessages);
      return { messages: trimmedMessages };
    });
  },
  
  removeMessage: (id) => {
    set((state) => ({
      messages: state.messages.filter((msg) => msg.id !== id),
    }));
  },
  
  clearMessages: () => {
    set({ messages: [] });
  },
}));

