'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export default function OAuthCallbackPage() {
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  useEffect(() => {
    const handleCallback = async () => {
      try {
        console.log('Callback page: Handling OAuth callback');
        console.log('Current URL:', window.location.href);
        console.log('URL search params:', window.location.search);

        const supabase = createClient();

        // Check if there's an active session (Supabase should have established it)
        const { data: { session }, error: sessionError } = await supabase.auth.getSession();

        console.log('Session check result:', session, 'error:', sessionError);

        if (sessionError) {
          console.error('Session error:', sessionError);
          setError(sessionError.message || 'Failed to establish session');
          return;
        }

        if (session) {
          console.log('Session found:', session.user?.email);
          router.push('/game');
          return;
        }

        // If no session, check for OAuth errors
        const urlParams = new URLSearchParams(window.location.search);
        const error = urlParams.get('error');
        const errorDescription = urlParams.get('error_description');

        if (error) {
          console.error('OAuth error:', error, errorDescription);
          setError(errorDescription || error || 'OAuth authentication failed');
          return;
        }

        // If no session and no error, something went wrong
        console.error('No session established and no error reported');
        setError('Authentication failed - please try again');

      } catch (err: any) {
        console.log('Callback error:', err);
        setError(err.message || 'An unexpected error occurred');
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