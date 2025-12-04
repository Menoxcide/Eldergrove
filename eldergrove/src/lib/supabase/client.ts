import { createBrowserClient } from '@supabase/ssr'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing Supabase environment variables:', {
    url: !!supabaseUrl,
    key: !!supabaseKey
  });
  throw new Error('Supabase environment variables not configured');
}

export const createClient = () => {
  try {
    const client = createBrowserClient(supabaseUrl, supabaseKey);
    return client;
  } catch (error) {
    console.error('Failed to create Supabase client:', error);
    throw error;
  }
}