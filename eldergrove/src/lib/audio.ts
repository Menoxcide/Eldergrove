import { Howl, Howler } from 'howler';

// Create sound effects with fallbacks (WAV first since we generate those)
// Only initialize in browser environment to prevent build-time errors
let plantSound: Howl | null = null;
let harvestSound: Howl | null = null;
let collectSound: Howl | null = null;

if (typeof window !== 'undefined') {
  plantSound = new Howl({
    src: ['/audio/plant.wav', '/audio/plant.mp3'],
    volume: 0.5,
    preload: true,
    onloaderror: (id: number, error: unknown) => {
      console.warn('Failed to load plant sound:', error);
    },
    onplayerror: (id: number, error: unknown) => {
      console.warn('Failed to play plant sound:', error);
    }
  });

  harvestSound = new Howl({
    src: ['/audio/harvest.wav', '/audio/harvest.mp3'],
    volume: 0.5,
    preload: true,
    onloaderror: (id: number, error: unknown) => {
      console.warn('Failed to load harvest sound:', error);
    },
    onplayerror: (id: number, error: unknown) => {
      console.warn('Failed to play harvest sound:', error);
    }
  });

  collectSound = new Howl({
    src: ['/audio/collect.wav', '/audio/collect.mp3'],
    volume: 0.5,
    preload: true,
    onloaderror: (id: number, error: unknown) => {
      console.warn('Failed to load collect sound:', error);
    },
    onplayerror: (id: number, error: unknown) => {
      console.warn('Failed to play collect sound:', error);
    }
  });
}

// Play sound effects
export const playPlantSound = () => {
  if (plantSound) {
    plantSound.play();
  }
};

export const playHarvestSound = () => {
  if (harvestSound) {
    harvestSound.play();
  }
};

export const playCollectSound = () => {
  if (collectSound) {
    collectSound.play();
  }
};

// Mute/unmute all sounds
let isMuted = false;

export const toggleMute = () => {
  isMuted = !isMuted;
  if (typeof window !== 'undefined') {
    Howler.mute(isMuted);
  }
};

export const isAudioMuted = () => isMuted;