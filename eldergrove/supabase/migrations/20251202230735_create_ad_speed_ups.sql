-- Create ad_watches table to track ad views for production speed-ups
CREATE TABLE IF NOT EXISTS public.ad_watches (
  id BIGSERIAL PRIMARY KEY,
  player_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  watched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  production_type TEXT NOT NULL CHECK (production_type IN ('farm', 'factory', 'zoo', 'mining')),
  production_id INTEGER NOT NULL,
  minutes_reduced INTEGER NOT NULL DEFAULT 30,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create index for efficient hourly limit queries
CREATE INDEX IF NOT EXISTS idx_ad_watches_player_watched_at 
ON public.ad_watches(player_id, watched_at DESC);

-- Enable RLS
ALTER TABLE public.ad_watches ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Players can only see their own ad watches
CREATE POLICY "Players can view their own ad watches"
ON public.ad_watches
FOR SELECT
USING (auth.uid() = player_id);

-- RLS Policy: Players can insert their own ad watches
CREATE POLICY "Players can insert their own ad watches"
ON public.ad_watches
FOR INSERT
WITH CHECK (auth.uid() = player_id);

COMMENT ON TABLE public.ad_watches IS 'Tracks ad watches for production speed-ups. Used to enforce hourly limits.';
COMMENT ON COLUMN public.ad_watches.production_type IS 'Type of production: farm, factory, or zoo';
COMMENT ON COLUMN public.ad_watches.production_id IS 'ID of the production item (plot_index for farm, slot for factory, enclosure_id for zoo)';
COMMENT ON COLUMN public.ad_watches.minutes_reduced IS 'Number of minutes reduced from production time';

