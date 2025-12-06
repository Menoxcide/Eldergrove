import { create } from 'zustand';

interface AdOverlayState {
  isVisible: boolean;
  duration: number;
  showOverlay: (duration: number) => void;
  hideOverlay: () => void;
}

export const useAdOverlayStore = create<AdOverlayState>((set) => ({
  isVisible: false,
  duration: 30000, // Default 30 seconds
  showOverlay: (duration: number) => set({ isVisible: true, duration }),
  hideOverlay: () => set({ isVisible: false }),
}));

