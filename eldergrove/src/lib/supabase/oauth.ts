import { createClient } from '@/lib/supabase/client';

export const signInWithGoogle = async () => {
  const supabase = createClient();

  // Set redirectTo to our application callback page
  const redirectTo = `${window.location.origin}/auth/callback`;
  console.log('OAuth redirectTo URL:', redirectTo);

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo,
    },
  });

  console.log('Sign in with Google response:', { data, error });

  if (error) {
    console.error('Error signing in with Google:', error);
    return { error };
  }

  // Redirect user to the authorization URL
  if (data?.url) {
    console.log('Redirecting to OAuth provider:', data.url);
    window.location.href = data.url;
  }

  return { data };
};
