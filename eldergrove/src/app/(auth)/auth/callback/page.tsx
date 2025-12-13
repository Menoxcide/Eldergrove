'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { useErrorHandler } from '@/hooks/useErrorHandler';

export default function OAuthCallbackPage() {
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const { handleError } = useErrorHandler();

  useEffect(() => {
    const handleCallback = async () => {
      try {
        const supabase = createClient();

        // Check if there's an active session (Supabase should have established it)
        const { data: { session }, error: sessionError } = await supabase.auth.getSession();

        if (process.env.NODE_ENV === 'development') {
          console.log('Session check result:', session, 'error:', sessionError);
        }

        if (sessionError) {
          handleError(sessionError, 'Session error during OAuth callback');
          setError(sessionError.message || 'Failed to establish session');
          return;
        }

        if (session) {
          if (process.env.NODE_ENV === 'development') {
            console.log('Session found:', session.user?.email);
          }
          router.push('/game');
          return;
        }

        // If no session, check for OAuth errors
        const urlParams = new URLSearchParams(window.location.search);
        const error = urlParams.get('error');
        const errorDescription = urlParams.get('error_description');

        if (error) {
          handleError(new Error(errorDescription || error || 'OAuth authentication failed'), 'OAuth error during callback');
          setError(errorDescription || error || 'OAuth authentication failed');
          return;
        }

        // If no session and no error, something went wrong
        handleError(new Error('No session established and no error reported'), 'OAuth callback failed - no session or error');
        setError('Authentication failed - please try again');

      } catch (err: unknown) {
        if (process.env.NODE_ENV === 'development') {
          console.log('Callback error:', err);
        }
        const errorMessage = err instanceof Error ? err.message : 'An unexpected error occurred'
        setError(errorMessage);
      }
    };

    handleCallback();
  }, [router]);

  if (error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 flex items-center justify-center p-8">
        <div className="w-full max-w-md p-8 space-y-6 bg-white/10 backdrop-blur-md rounded-3xl shadow-2xl border border-white/20 mx-auto">
          <div className="text-center">
            <h2 className="text-3xl font-bold text-white mb-2">Authentication Error</h2>
            <p className="text-slate-300 text-sm mb-6">{error}</p>
            <button
              onClick={() => router.push('/login')}
              className="bg-gradient-to-r from-emerald-500 to-teal-600 hover:from-emerald-600 hover:to-teal-700 text-white font-bold py-3 px-6 rounded-xl shadow-lg hover:shadow-xl transform hover:-translate-y-0.5 transition-all duration-300 focus:outline-none focus:ring-4 focus:ring-emerald-400/50"
            >
              Return to Login
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/50 to-slate-900 flex items-center justify-center p-8">
      <div className="w-full max-w-md p-8 space-y-6 bg-white/10 backdrop-blur-md rounded-3xl shadow-2xl border border-white/20 mx-auto">
        <div className="text-center">
          <h2 className="text-3xl font-bold text-white mb-2">Authenticating...</h2>
          <p className="text-slate-300 text-sm">Please wait while we complete your authentication</p>
          <div className="mt-6 flex justify-center">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-500"></div>
          </div>
        </div>
      </div>
    </div>
  );
}