-- Create town expansion system (expandable town grid)

-- Add town_size column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'town_size'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN town_size integer DEFAULT 10;
  END IF;
END $$;

-- Create town_expansions table to track expansion history
CREATE TABLE IF NOT EXISTS public.town_expansions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('north', 'south', 'east', 'west', 'all')),
  old_size integer NOT NULL,
  new_size integer NOT NULL,
  cost_crystals integer NOT NULL,
  expanded_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.town_expansions ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view own expansions
CREATE POLICY "Players can view own expansions" ON public.town_expansions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Policy: Players can insert own expansions
CREATE POLICY "Players can insert own expansions" ON public.town_expansions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.town_expansions;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_town_expansions_player ON public.town_expansions(player_id);

-- Function to expand town
CREATE OR REPLACE FUNCTION public.expand_town(
  p_direction text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_size integer;
  v_new_size integer;
  v_expansion_cost integer;
  v_current_crystals bigint;
  v_result jsonb;
BEGIN
  -- Validate direction
  IF p_direction NOT IN ('north', 'south', 'east', 'west', 'all') THEN
    RAISE EXCEPTION 'Invalid direction: %. Must be north, south, east, west, or all', p_direction;
  END IF;

  -- Get current town size
  SELECT COALESCE(town_size, 10) INTO v_current_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate new size and cost
  IF p_direction = 'all' THEN
    v_new_size := v_current_size + 5; -- Expand by 5x5
    v_expansion_cost := v_current_size * 1000; -- Cost scales with current size
  ELSE
    v_new_size := v_current_size + 2; -- Expand by 2 in one direction
    v_expansion_cost := v_current_size * 500;
  END IF;

  -- Maximum size limit
  IF v_new_size > 30 THEN
    RAISE EXCEPTION 'Maximum town size (30x30) reached';
  END IF;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_expansion_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_expansion_cost, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_expansion_cost,
      town_size = v_new_size
  WHERE id = v_player_id;

  -- Record expansion
  INSERT INTO public.town_expansions (
    player_id,
    direction,
    old_size,
    new_size,
    cost_crystals
  )
  VALUES (
    v_player_id,
    p_direction,
    v_current_size,
    v_new_size,
    v_expansion_cost
  );

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'old_size', v_current_size,
    'new_size', v_new_size,
    'cost_crystals', v_expansion_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.expand_town(text) IS 'Expand town grid size. Direction: north, south, east, west, or all (default).';

-- Function to get expansion cost
CREATE OR REPLACE FUNCTION public.get_expansion_cost(
  p_direction text DEFAULT 'all'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_size integer;
  v_cost integer;
BEGIN
  -- Get current town size
  SELECT COALESCE(town_size, 10) INTO v_current_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate cost
  IF p_direction = 'all' THEN
    v_cost := v_current_size * 1000;
  ELSE
    v_cost := v_current_size * 500;
  END IF;

  RETURN v_cost;
END;
$$;

COMMENT ON FUNCTION public.get_expansion_cost(text) IS 'Get the cost to expand town in a given direction';

