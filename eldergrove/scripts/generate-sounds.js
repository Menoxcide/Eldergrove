const fs = require('fs');
const path = require('path');
const { WaveFile } = require('wavefile');

// Ensure audio directory exists
const audioDir = path.join(__dirname, '..', 'public', 'audio');
if (!fs.existsSync(audioDir)) {
  fs.mkdirSync(audioDir, { recursive: true });
}

// Helper function to generate a tone
function generateTone(frequency, duration, sampleRate = 44100, volume = 0.3) {
  const samples = Math.floor(sampleRate * duration);
  const buffer = new Array(samples);
  
  for (let i = 0; i < samples; i++) {
    const t = i / sampleRate;
    // Generate a sine wave with a fade-in and fade-out envelope
    const envelope = Math.min(
      t / 0.01, // Fade in over 10ms
      (duration - t) / 0.05, // Fade out over 50ms
      1.0
    );
    buffer[i] = Math.sin(2 * Math.PI * frequency * t) * envelope * volume;
  }
  
  return buffer;
}

// Helper function to generate a tone with frequency sweep
function generateSweep(startFreq, endFreq, duration, sampleRate = 44100, volume = 0.3) {
  const samples = Math.floor(sampleRate * duration);
  const buffer = new Array(samples);
  
  for (let i = 0; i < samples; i++) {
    const t = i / sampleRate;
    const progress = t / duration;
    const frequency = startFreq + (endFreq - startFreq) * progress;
    
    // Envelope with fade-in and fade-out
    const envelope = Math.min(
      t / 0.01,
      (duration - t) / 0.05,
      1.0
    );
    buffer[i] = Math.sin(2 * Math.PI * frequency * t) * envelope * volume;
  }
  
  return buffer;
}

// Helper function to combine multiple tones
function combineTones(...tones) {
  const maxLength = Math.max(...tones.map(t => t.length));
  const combined = new Array(maxLength).fill(0);
  
  tones.forEach(tone => {
    tone.forEach((sample, i) => {
      if (i < combined.length) {
        combined[i] += sample;
      }
    });
  });
  
  // Normalize to prevent clipping
  const max = Math.max(...combined.map(Math.abs));
  if (max > 1.0) {
    return combined.map(s => s / max);
  }
  return combined;
}

// Generate plant sound: gentle rising tone (like planting)
function generatePlantSound() {
  const tone1 = generateSweep(300, 400, 0.15, 44100, 0.25);
  const tone2 = generateTone(200, 0.15, 44100, 0.15);
  return combineTones(tone1, tone2);
}

// Generate harvest sound: satisfying completion chime
function generateHarvestSound() {
  const tone1 = generateTone(523.25, 0.1, 44100, 0.2); // C5
  const tone2 = generateTone(659.25, 0.15, 44100, 0.2); // E5
  const tone3 = generateTone(783.99, 0.2, 44100, 0.2); // G5
  
  // Offset tones slightly for a chord effect
  const offset1 = new Array(Math.floor(44100 * 0.05)).fill(0).concat(tone1);
  const offset2 = new Array(Math.floor(44100 * 0.1)).fill(0).concat(tone2);
  
  return combineTones(offset1, offset2, tone3);
}

// Generate collect sound: quick chime
function generateCollectSound() {
  const tone1 = generateTone(880, 0.08, 44100, 0.3); // A5
  const tone2 = generateTone(1108.73, 0.1, 44100, 0.25); // C#6
  const offset = new Array(Math.floor(44100 * 0.02)).fill(0).concat(tone2);
  return combineTones(tone1, offset);
}

// Convert float array to 16-bit PCM Int16Array
function floatTo16BitPCM(float32Array) {
  const int16Array = new Int16Array(float32Array.length);
  for (let i = 0; i < float32Array.length; i++) {
    let s = Math.max(-1, Math.min(1, float32Array[i]));
    int16Array[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
  }
  return int16Array;
}

// Save WAV file
function saveWavFile(filename, samples, sampleRate = 44100) {
  const wav = new WaveFile();
  const pcmData = floatTo16BitPCM(samples);
  
  // Create a buffer from Int16Array
  const buffer = Buffer.from(pcmData.buffer);
  
  wav.fromScratch(1, sampleRate, '16', buffer);
  
  const filePath = path.join(audioDir, filename);
  fs.writeFileSync(filePath, wav.toBuffer());
  console.log(`Generated: ${filename} (${(wav.toBuffer().length / 1024).toFixed(2)} KB)`);
}

// Generate all sounds
console.log('Generating sound effects...');

const plantSamples = generatePlantSound();
saveWavFile('plant.wav', plantSamples);

const harvestSamples = generateHarvestSound();
saveWavFile('harvest.wav', harvestSamples);

const collectSamples = generateCollectSound();
saveWavFile('collect.wav', collectSamples);

// Also generate MP3 versions using the same WAV files (for now, just copy)
// In a real scenario, you might want to use ffmpeg or another tool to convert
// For now, we'll just ensure WAV files exist and Howler will use them
console.log('Sound generation complete!');

