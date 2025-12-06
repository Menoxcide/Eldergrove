CREATE OR REPLACE FUNCTION public.add_animal_to_enclosure(
  p_enclosure_id integer,
  p_animal_type_id integer,
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
  v_animal_type record;
  v_current_crystals bigint;
  v_rows_affected integer;
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

  -- Get animal type
  SELECT * INTO v_animal_type
  FROM public.animal_types
  WHERE id = p_animal_type_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Animal type % not found', p_animal_type_id;
  END IF;

  -- Check if slot is already occupied
  IF p_slot = 1 AND v_enclosure.animal1_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 1 is already occupied';
  END IF;

  IF p_slot = 2 AND v_enclosure.animal2_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 2 is already occupied';
  END IF;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player profile not found';
  END IF;

  IF v_current_crystals < v_animal_type.base_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_animal_type.base_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals with verification
  UPDATE public.profiles
  SET crystals = crystals - v_animal_type.base_cost_crystals
  WHERE id = v_player_id;
  
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'Failed to deduct crystals - profile update did not affect any rows';
  END IF;

  -- Add animal to enclosure with verification
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_id = p_animal_type_id,
        animal1_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 1';
    END IF;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_id = p_animal_type_id,
        animal2_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 2';
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.add_animal_to_enclosure(integer, integer, integer) IS 'Add an animal to an enclosure slot (fixed to verify crystal deduction succeeds)';

