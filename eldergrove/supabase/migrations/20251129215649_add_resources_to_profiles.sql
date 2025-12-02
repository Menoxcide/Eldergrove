-- Add resources jsonb column to profiles for storing inventory resources like wheat, crystals etc.
alter table public.profiles 
add column resources jsonb default '{}'::jsonb;