'use client';

import { Toaster } from 'react-hot-toast';

export function ToastProvider() {
  return (
    <Toaster
      position="top-center"
      toastOptions={{
        duration: 3000,
        style: {
          background: '#1e293b',
          color: '#f8fafc',
          border: '1px solid #334155',
          borderRadius: '0.5rem',
          boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
        },
        success: {
          style: {
            background: '#166534',
            border: '1px solid #15803d',
          },
        },
        error: {
          style: {
            background: '#991b1b',
            border: '1px solid #b91c1c',
          },
        },
      }}
    />
  );
}