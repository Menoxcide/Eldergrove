'use client';

import React from 'react';
import AdOverlay from './AdOverlay';
import { useAdOverlayStore } from '@/stores/useAdOverlayStore';

const AdOverlayProvider: React.FC = () => {
  const { isVisible, duration, hideOverlay } = useAdOverlayStore();

  return (
    <AdOverlay
      isVisible={isVisible}
      duration={duration}
      onComplete={hideOverlay}
    />
  );
};

export default AdOverlayProvider;

