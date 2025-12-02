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
    let isMounted = true;

    // In production, trust the middleware for initial authentication
    // Just do a quick session check to confirm
    const quickSessionCheck = async () => {
      try {
        const supabase = createClient();
        const { data: { session } } = await supabase.auth.getSession();

        if (session && isMounted) {
          console.log('ProtectedLayout: Session confirmed:', session.user?.email);
          setAuthenticated(true);
          setLoading(false);
        } else {
          console.log('ProtectedLayout: No session found, redirecting to login');
          if (isMounted) {
            router.replace('/login');
          }
        }
      } catch (error) {
        console.error('ProtectedLayout: Error checking session:', error);
        if (isMounted) {
          router.replace('/login');
        }
      }
    };

    // Small delay to let middleware/session establish
    const timer = setTimeout(quickSessionCheck, 500);

    return () => {
      isMounted = false;
      clearTimeout(timer);
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