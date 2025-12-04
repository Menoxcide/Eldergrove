-- Add zoo enclosure limits with exponential crystal costs
-- First 3 enclosures are free, then exponential pricing: 500, 1000, 2000, 4000, etc.

-- Add max_enclosures column to profiles
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'max_enclosures'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN max_enclosures integer DEFAULT 3;
  END IF;
END $$;

-- Function to calculate enclosure purchase cost
CREATE OR REPLACE FUNCTION public.get_enclosure_cost(p_current_max integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- First 3 are free, then exponential: 500 * 2^(current_max - 3)
  IF p_current_max < 3 THEN
    RETURN 0;
  END IF;
  RETURN 500 * POWER(2, p_current_max - 3)::integer;
END;
$$;

COMMENT ON FUNCTION public.get_enclosure_cost(integer) IS 'Calculate cost for next enclosure slot. Returns 0 for first 3, then exponential pricing.';

-- Function to get next enclosure cost (for UI display)
CREATE OR REPLACE FUNCTION public.get_next_enclosure_cost()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_max integer;
  v_current_count integer;
  v_cost integer;
BEGIN
  -- Get current max_enclosures (defaults to 3 if null)
  SELECT COALESCE(max_enclosures, 3) INTO v_current_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Get current enclosure count
  SELECT COUNT(*) INTO v_current_count
  FROM public.zoo_enclosures
  WHERE player_id = v_player_id;

  -- Calculate cost for next enclosure
  v_cost := public.get_enclosure_cost(v_current_max);

  RETURN jsonb_build_object(
    'current_count', v_current_count,
    'max_enclosures', v_current_max,
    'can_create_free', v_current_count < 3,
    'next_cost', v_cost,
    'at_limit', v_current_count >= v_current_max
  );
END;
$$;

COMMENT ON FUNCTION public.get_next_enclosure_cost() IS 'Get information about enclosure limits and costs for current player';

-- Drop existing create_enclosure function first (since we're changing return type)
DROP FUNCTION IF EXISTS public.create_enclosure(text);

-- Recreate create_enclosure function to handle limits and costs
CREATE OR REPLACE FUNCTION public.create_enclosure(p_enclosure_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure_id integer;
  v_current_max integer;
  v_current_count integer;
  v_cost integer;
  v_current_crystals bigint;
BEGIN
  -- Get current max_enclosures (defaults to 3 if null)
  SELECT COALESCE(max_enclosures, 3) INTO v_current_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Get current enclosure count
  SELECT COUNT(*) INTO v_current_count
  FROM public.zoo_enclosures
  WHERE player_id = v_player_id;

  -- Check if at limit
  IF v_current_count >= v_current_max THEN
    -- Calculate cost for next slot
    v_cost := public.get_enclosure_cost(v_current_max);
    
    -- Get current crystals
    SELECT crystals INTO v_current_crystals
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_crystals < v_cost THEN
      RAISE EXCEPTION 'Insufficient crystals: required % for next enclosure slot, available %', v_cost, v_current_crystals;
    END IF;

    -- Deduct crystals and increase max_enclosures
    UPDATE public.profiles
    SET crystals = crystals - v_cost,
        max_enclosures = max_enclosures + 1
    WHERE id = v_player_id;
  END IF;

  -- Create the enclosure
  INSERT INTO public.zoo_enclosures (player_id, enclosure_name)
  VALUES (v_player_id, p_enclosure_name)
  RETURNING id INTO v_enclosure_id;

  -- Return result with cost info
  RETURN jsonb_build_object(
    'success', true,
    'enclosure_id', v_enclosure_id,
    'cost_paid', CASE WHEN v_current_count >= v_current_max THEN v_cost ELSE 0 END,
    'new_max_enclosures', CASE WHEN v_current_count >= v_current_max THEN v_current_max + 1 ELSE v_current_max END
  );
END;
$$;

COMMENT ON FUNCTION public.create_enclosure(text) IS 'Create a new enclosure. Automatically purchases slot expansion if at limit. Returns cost information.';

