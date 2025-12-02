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
      // Give OAuth callbacks more time to establish session
      await new Promise(resolve => setTimeout(resolve, 1500));

      const { data: { session }, error } = await supabase.auth.getSession();
      console.log('ProtectedLayout: Session check result:', session ? 'Session found' : 'No session', 'error:', error);

      if (session) {
        console.log('ProtectedLayout: User authenticated:', session.user?.email);
      }

      if (isMounted) {
        if (!session) {
          console.log('ProtectedLayout: No session, redirecting to login');
          router.replace('/login');
        } else {
          console.log('ProtectedLayout: Session confirmed, showing game');
          setAuthenticated(true);
          setLoading(false);
        }
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