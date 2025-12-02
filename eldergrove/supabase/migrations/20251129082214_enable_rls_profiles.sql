-- Enable Row Level Security (RLS) on profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policy for SELECT: Users can view their own profile
CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT
  USING ( auth.uid() = id );

-- Policy for UPDATE: Users can update their own profile
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE
  USING ( auth.uid() = id );