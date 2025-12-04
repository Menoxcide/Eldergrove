-- Improve animal breeding system: add level-based breeding time scaling, production scaling, and remove animal functionality

-- Update start_breeding function to scale breeding time exponentially with animal level
-- Formula: base_time * (1.1 ^ max(animal1_level, animal2_level))
CREATE OR REPLACE FUNCTION public.start_breeding(p_enclosure_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal1_type record;
  v_animal2_type record;
  v_breeding_time_minutes numeric;
  v_base_time_minutes integer;
  v_max_level integer;
BEGIN
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  IF v_enclosure.animal1_id IS NULL OR v_enclosure.animal2_id IS NULL THEN
    RAISE EXCEPTION 'Both slots must be filled to breed';
  END IF;

  IF v_enclosure.breeding_started_at IS NOT NULL AND v_enclosure.breeding_completes_at > now() THEN
    RAISE EXCEPTION 'Breeding already in progress';
  END IF;

  -- Get animal types
  SELECT * INTO v_animal1_type FROM public.animal_types WHERE id = v_enclosure.animal1_id;
  SELECT * INTO v_animal2_type FROM public.animal_types WHERE id = v_enclosure.animal2_id;

  -- Check that both animals are the same type
  IF v_animal1_type.id != v_animal2_type.id THEN
    RAISE EXCEPTION 'Can only breed two animals of the same type. You have % and %', v_animal1_type.name, v_animal2_type.name;
  END IF;

  -- Check that both animals are below max level
  IF COALESCE(v_enclosure.animal1_level, 0) >= 10 OR COALESCE(v_enclosure.animal2_level, 0) >= 10 THEN
    RAISE EXCEPTION 'Cannot breed animals that are already at maximum level (10)';
  END IF;

  -- Calculate base breeding time (max of both animals' base times)
  v_base_time_minutes := GREATEST(v_animal1_type.breeding_time_minutes, v_animal2_type.breeding_time_minutes);
  
  -- Get max level of the two animals
  v_max_level := GREATEST(COALESCE(v_enclosure.animal1_level, 0), COALESCE(v_enclosure.animal2_level, 0));
  
  -- Calculate breeding time with exponential scaling: base_time * (1.1 ^ max_level)
  v_breeding_time_minutes := v_base_time_minutes * POWER(1.1, v_max_level);

  -- Start breeding
  UPDATE public.zoo_enclosures
  SET breeding_started_at = now(),
      breeding_completes_at = now() + (ROUND(v_breeding_time_minutes) || ' minutes')::interval
  WHERE id = p_enclosure_id;
END;
$$;

COMMENT ON FUNCTION public.start_breeding(integer) IS 'Start breeding between two animals of the same type in an enclosure. Breeding time scales exponentially with animal level (1.1^level).';

-- Update collect_animal_production function to scale production quantity with animal level
-- Formula: base_quantity * (1 + level * 0.1)
CREATE OR REPLACE FUNCTION public.collect_animal_production(
  p_enclosure_id integer,
  p_slot integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal_type record;
  v_animal_id integer;
  v_animal_level integer;
  v_produced_at timestamptz;
  v_item_id integer;
  v_base_quantity integer;
  v_quantity integer;
  v_interval_minutes integer;
  v_result jsonb;
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

  -- Get animal info based on slot
  IF p_slot = 1 THEN
    v_animal_id := v_enclosure.animal1_id;
    v_animal_level := COALESCE(v_enclosure.animal1_level, 0);
    v_produced_at := v_enclosure.animal1_produced_at;
  ELSE
    v_animal_id := v_enclosure.animal2_id;
    v_animal_level := COALESCE(v_enclosure.animal2_level, 0);
    v_produced_at := v_enclosure.animal2_produced_at;
  END IF;

  IF v_animal_id IS NULL THEN
    RAISE EXCEPTION 'No animal in slot %', p_slot;
  END IF;

  -- Get animal type
  SELECT * INTO v_animal_type
  FROM public.animal_types
  WHERE id = v_animal_id;

  v_item_id := v_animal_type.produces_item_id;
  v_base_quantity := v_animal_type.produces_quantity;
  v_interval_minutes := v_animal_type.produces_interval_minutes;

  -- Check if production is ready
  IF v_produced_at IS NULL OR v_produced_at + (v_interval_minutes || ' minutes')::interval > now() THEN
    RAISE EXCEPTION 'Animal production not ready yet';
  END IF;

  -- Calculate quantity with level scaling: base_quantity * (1 + level * 0.1)
  v_quantity := ROUND(v_base_quantity * (1.0 + (v_animal_level * 0.1)));

  -- Award items
  IF v_item_id IS NOT NULL THEN
    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_item_id, v_quantity::bigint)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + excluded.quantity;
  END IF;

  -- Update production time
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_produced_at = now()
    WHERE id = p_enclosure_id;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_produced_at = now()
    WHERE id = p_enclosure_id;
  END IF;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'item_id', v_item_id,
    'quantity', v_quantity
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.collect_animal_production(integer, integer) IS 'Collect production from an animal in an enclosure. Production quantity scales with animal level (1 + level * 0.1).';

-- Function to remove animal from enclosure and return it to inventory
CREATE OR REPLACE FUNCTION public.remove_animal_from_enclosure(
  p_enclosure_id integer,
  p_slot integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal_type_id integer;
  v_animal_level integer;
  v_item_id integer;
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

  -- Get animal info based on slot
  IF p_slot = 1 THEN
    v_animal_type_id := v_enclosure.animal1_id;
    v_animal_level := COALESCE(v_enclosure.animal1_level, 0);
    
    IF v_animal_type_id IS NULL THEN
      RAISE EXCEPTION 'No animal in slot 1';
    END IF;
  ELSE
    v_animal_type_id := v_enclosure.animal2_id;
    v_animal_level := COALESCE(v_enclosure.animal2_level, 0);
    
    IF v_animal_type_id IS NULL THEN
      RAISE EXCEPTION 'No animal in slot 2';
    END IF;
  END IF;

  -- Calculate item_id for the animal: 1000 + (animal_type_id * 100) + level
  v_item_id := 1000 + (v_animal_type_id * 100) + v_animal_level;

  -- Add animal back to inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_item_id, 1)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + 1;

  -- Clear the slot in the enclosure
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_id = NULL,
        animal1_level = NULL,
        animal1_produced_at = NULL
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to remove animal from slot 1';
    END IF;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_id = NULL,
        animal2_level = NULL,
        animal2_produced_at = NULL
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to remove animal from slot 2';
    END IF;
  END IF;

  -- If both slots are now empty and breeding was in progress, reset breeding
  IF (SELECT animal1_id IS NULL AND animal2_id IS NULL FROM public.zoo_enclosures WHERE id = p_enclosure_id) THEN
    UPDATE public.zoo_enclosures
    SET breeding_started_at = NULL,
        breeding_completes_at = NULL
    WHERE id = p_enclosure_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_animal_from_enclosure(integer, integer) IS 'Remove an animal from an enclosure slot and return it to inventory. Supports leveled animals.';

