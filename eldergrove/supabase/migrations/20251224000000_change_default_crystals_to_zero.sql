-- Change default crystal count from 500 to 0 for new players
-- Existing players will retain their current crystal balance

ALTER TABLE public.profiles 
ALTER COLUMN crystals SET DEFAULT 0;

COMMENT ON COLUMN public.profiles.crystals IS 'Player crystal balance. Default is 0 for new players.';

