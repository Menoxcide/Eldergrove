-- Add functions to cancel breeding and production processes

-- Function to cancel breeding
CREATE OR REPLACE FUNCTION public.cancel_breeding(p_enclosure_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
BEGIN
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Check if breeding is actually in progress
  IF v_enclosure.breeding_started_at IS NULL OR v_enclosure.breeding_completes_at IS NULL THEN
    RAISE EXCEPTION 'No breeding process in progress to cancel';
  END IF;

  -- Cancel breeding by resetting timestamps
  UPDATE public.zoo_enclosures
  SET breeding_started_at = NULL,
      breeding_completes_at = NULL
  WHERE id = p_enclosure_id AND player_id = v_player_id;
END;
$$;

COMMENT ON FUNCTION public.cancel_breeding(integer) IS 'Cancel an in-progress breeding process by resetting breeding timestamps';

-- Function to cancel/reset production
CREATE OR REPLACE FUNCTION public.cancel_production(
  p_enclosure_id integer,
  p_slot integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
BEGIN
  -- Validate slot
  IF p_slot NOT IN (1, 2) THEN
    RAISE EXCEPTION 'Invalid slot: % (must be 1 or 2)', p_slot;
  END IF;
  
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Check if slot has an animal
  IF p_slot = 1 AND v_enclosure.animal1_id IS NULL THEN
    RAISE EXCEPTION 'No animal in slot 1 to cancel production for';
  END IF;

  IF p_slot = 2 AND v_enclosure.animal2_id IS NULL THEN
    RAISE EXCEPTION 'No animal in slot 2 to cancel production for';
  END IF;

  -- Reset production timestamp (this resets the timer)
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_produced_at = NULL
    WHERE id = p_enclosure_id AND player_id = v_player_id;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_produced_at = NULL
    WHERE id = p_enclosure_id AND player_id = v_player_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.cancel_production(integer, integer) IS 'Cancel/reset production timer for an animal in an enclosure slot';

