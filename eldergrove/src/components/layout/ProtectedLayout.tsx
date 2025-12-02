'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

interface ProtectedLayoutProps {
  children: React.ReactNode;
}

const ProtectedLayout: React.FC<ProtectedLayoutProps> = ({ children }) => {
  const [loading, setLoading] = useState(true);
  const [authenticated, setAuthenticated] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    let isMounted = true;

    const checkSession = async () => {
      console.log('ProtectedLayout: Checking session...');

      // Try multiple times with increasing delays to handle production timing issues
      for (let attempt = 1; attempt <= 3; attempt++) {
        console.log(`ProtectedLayout: Session check attempt ${attempt}`);

        const { data: { session }, error } = await supabase.auth.getSession();
        console.log('ProtectedLayout: Session check result:', session ? 'Session found' : 'No session', 'error:', error);

        if (session) {
          console.log('ProtectedLayout: User authenticated:', session.user?.email);
          if (isMounted) {
            setAuthenticated(true);
            setLoading(false);
          }
          return;
        }

        // Wait before next attempt (1.5s, 2.5s, 3.5s)
        if (attempt < 3) {
          await new Promise(resolve => setTimeout(resolve, 1000 + attempt * 1000));
        }
      }

      // If we get here, no session was found after all attempts
      console.log('ProtectedLayout: No session found after all attempts, redirecting to login');
      if (isMounted) {
        router.replace('/login');
      }
    };

    checkSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      console.log('ProtectedLayout: Auth state change:', event, session ? 'Session present' : 'No session');

      if (session) {
        console.log('ProtectedLayout: Auth state change - User:', session.user?.email);
      }

      if (isMounted) {
        if (!session) {
          console.log('ProtectedLayout: Auth state change - No session, redirecting to login');
          router.replace('/login');
        } else {
          console.log('ProtectedLayout: Auth state change - Session confirmed, showing game');
          setAuthenticated(true);
          setLoading(false);
        }
      }
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, [router]);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-slate-900 via-purple-900/25 to-slate-900">
        <div className="w-16 h-16 border-4 border-emerald-400/20 border-t-emerald-400 rounded-full animate-spin"></div>
      </div>
    );
  }

  if (!authenticated) {
    return null;
  }

  return <>{children}</>;
};

export default ProtectedLayout;