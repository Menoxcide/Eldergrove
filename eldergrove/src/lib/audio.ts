import { Howl, Howler } from 'howler';

// Create sound effects with fallbacks
const plantSound = new Howl({
  src: ['/audio/plant.mp3', '/audio/plant.wav'],
  volume: 0.5,
  onloaderror: (id: number, error: any) => {
    console.warn('Failed to load plant sound:', error);
  },
  onplayerror: (id: number, error: any) => {
    console.warn('Failed to play plant sound:', error);
  }
});

const harvestSound = new Howl({
  src: ['/audio/harvest.mp3', '/audio/harvest.wav'],
  volume: 0.5,
  onloaderror: (id: number, error: any) => {
    console.warn('Failed to load harvest sound:', error);
  },
  onplayerror: (id: number, error: any) => {
    console.warn('Failed to play harvest sound:', error);
  }
});

const collectSound = new Howl({
  src: ['/audio/collect.mp3', '/audio/collect.wav'],
  volume: 0.5,
  onloaderror: (id: number, error: any) => {
    console.warn('Failed to load collect sound:', error);
  },
  onplayerror: (id: number, error: any) => {
    console.warn('Failed to play collect sound:', error);
  }
});

// Play sound effects
export const playPlantSound = () => {
  try {
    plantSound.play();
  } catch (error) {
    console.warn('Error playing plant sound:', error);
  }
};

export const playHarvestSound = () => {
  try {
    harvestSound.play();
  } catch (error) {
    console.warn('Error playing harvest sound:', error);
  }
};

export const playCollectSound = () => {
  try {
    collectSound.play();
  } catch (error) {
    console.warn('Error playing collect sound:', error);
  }
};

// Mute/unmute all sounds
let isMuted = false;

export const toggleMute = () => {
  isMuted = !isMuted;
  Howler.mute(isMuted);
};

export const isAudioMuted = () => isMuted;