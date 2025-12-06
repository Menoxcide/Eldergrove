'use client';

import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import ProgressBar from '@/components/ui/ProgressBar';

export interface AdOverlayProps {
  isVisible: boolean;
  duration: number; // Duration in milliseconds
  onComplete?: () => void;
}

const AdOverlay: React.FC<AdOverlayProps> = ({
  isVisible,
  duration,
  onComplete,
}) => {
  const [elapsed, setElapsed] = useState(0);
  const [startTime, setStartTime] = useState<number | null>(null);

  useEffect(() => {
    if (!isVisible) {
      setElapsed(0);
      setStartTime(null);
      return;
    }

    // Start the timer when overlay becomes visible
    const start = Date.now();
    setStartTime(start);

    const interval = setInterval(() => {
      const now = Date.now();
      const newElapsed = now - start;
      setElapsed(newElapsed);

      if (newElapsed >= duration) {
        clearInterval(interval);
        setElapsed(duration);
        onComplete?.();
      }
    }, 16); // Update roughly every frame (60fps)

    return () => {
      clearInterval(interval);
    };
  }, [isVisible, duration, onComplete]);

  // Reset elapsed when overlay is hidden externally (e.g., ad completes early)
  useEffect(() => {
    if (!isVisible && elapsed > 0) {
      setElapsed(0);
      setStartTime(null);
    }
  }, [isVisible, elapsed]);

  if (!isVisible) {
    return null;
  }

  const progress = Math.min(100, (elapsed / duration) * 100);
  const remainingSeconds = Math.ceil((duration - elapsed) / 1000);
  const formattedTime = `${Math.floor(remainingSeconds / 60)}:${String(remainingSeconds % 60).padStart(2, '0')}`;

  return createPortal(
    <div
      className="fixed inset-0 z-[99999] bg-black/90 backdrop-blur-sm flex items-center justify-center"
      style={{ pointerEvents: 'all' }}
      onContextMenu={(e) => e.preventDefault()}
    >
      {/* Prevent interaction with content behind */}
      <div className="absolute inset-0" />
      
      {/* Content */}
      <div className="relative z-10 flex flex-col items-center gap-6 p-8 max-w-md w-full mx-4">
        <div className="text-center space-y-4">
          <h2 className="text-3xl font-bold text-white mb-2">
            Watching Ad
          </h2>
          <p className="text-slate-300 text-lg">
            Please watch the ad to completion
          </p>
        </div>

        {/* Timer */}
        <div className="text-center">
          <div className="text-6xl font-mono font-bold text-white mb-2">
            {formattedTime}
          </div>
          <div className="text-slate-400 text-sm">
            Time remaining
          </div>
        </div>

        {/* Progress Bar */}
        <div className="w-full">
          <ProgressBar
            progress={progress}
            showLabel={true}
            label={`${Math.round(progress)}%`}
            className="w-full"
          />
        </div>

        {/* Instructions */}
        <div className="text-center text-slate-400 text-sm mt-4">
          <p>Do not close or minimize this window</p>
        </div>
      </div>
    </div>,
    document.body
  );
};

export default AdOverlay;

