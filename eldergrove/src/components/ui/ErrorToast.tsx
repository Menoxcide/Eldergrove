'use client';

import { ParsedError } from '@/lib/errorUtils';
import { getItemIcon } from '@/lib/itemUtils';

interface ErrorToastProps {
  error: ParsedError;
  onClose?: () => void;
}

export function ErrorToast({ error, onClose }: ErrorToastProps) {
  return (
    <div className="flex items-start gap-3 p-4 bg-gradient-to-r from-red-900/90 to-red-800/90 backdrop-blur-sm rounded-xl border-2 border-red-500/50 shadow-xl max-w-md">
      <div className="flex-shrink-0 text-3xl">{error.icon || '⚠️'}</div>
      <div className="flex-1 min-w-0">
        <div className="font-bold text-white text-lg mb-1">{error.title}</div>
        <div className="text-red-100 text-sm mb-2">{error.message}</div>
        
        {error.details && (
          <div className="mt-2 space-y-1">
            {error.details.required !== undefined && error.details.available !== undefined && (
              <div className="flex items-center gap-2 text-xs bg-red-950/50 px-2 py-1 rounded">
                {error.details.itemId && (
                  <span className="text-lg">{getItemIcon(error.details.itemId)}</span>
                )}
                <span className="text-red-200">Required:</span>
                <span className="text-white font-semibold">{error.details.required.toLocaleString()}</span>
                <span className="text-red-200">Available:</span>
                <span className="text-white font-semibold">{error.details.available.toLocaleString()}</span>
              </div>
            )}
            
            {error.details.maxSlots !== undefined && (
              <div className="flex items-center gap-2 text-xs bg-red-950/50 px-2 py-1 rounded">
                <span className="text-red-200">Slots:</span>
                <span className="text-white font-semibold">{error.details.currentSlots || 0}/{error.details.maxSlots}</span>
              </div>
            )}
            
            {error.details.itemName && error.details.itemId && (
              <div className="flex items-center gap-2 text-xs bg-red-950/50 px-2 py-1 rounded">
                <span className="text-lg">{getItemIcon(error.details.itemId)}</span>
                <span className="text-white">{error.details.itemName}</span>
              </div>
            )}
          </div>
        )}
        
        {error.suggestion && (
          <div className="mt-2 pt-2 border-t border-red-400/30">
            <div className="text-yellow-200 text-xs italic">{error.suggestion}</div>
          </div>
        )}
      </div>
      {onClose && (
        <button
          onClick={onClose}
          className="flex-shrink-0 text-red-200 hover:text-white transition-colors"
          aria-label="Close"
        >
          ✕
        </button>
      )}
    </div>
  );
}

