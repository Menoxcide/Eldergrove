-- Add animal level tracking and update breeding to only allow same-type breeding with leveling

-- Add level columns to zoo_enclosures for animals currently placed
ALTER TABLE public.zoo_enclosures
ADD COLUMN IF NOT EXISTS animal1_level integer DEFAULT 0 CHECK (animal1_level >= 0 AND animal1_level <= 10),
ADD COLUMN IF NOT EXISTS animal2_level integer DEFAULT 0 CHECK (animal2_level >= 0 AND animal2_level <= 10);

-- Update start_breeding function to only allow breeding same animal types
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
  v_breeding_time_minutes integer;
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

  -- Use longer breeding time
  v_breeding_time_minutes := GREATEST(v_animal1_type.breeding_time_minutes, v_animal2_type.breeding_time_minutes);

  -- Start breeding
  UPDATE public.zoo_enclosures
  SET breeding_started_at = now(),
      breeding_completes_at = now() + (v_breeding_time_minutes || ' minutes')::interval
  WHERE id = p_enclosure_id;
END;
$$;

COMMENT ON FUNCTION public.start_breeding(integer) IS 'Start breeding between two animals of the same type in an enclosure';

-- Update collect_bred_animal function to produce leveled animals
CREATE OR REPLACE FUNCTION public.collect_bred_animal(p_enclosure_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal1_type record;
  v_animal2_type record;
  v_result_level integer;
  v_result_item_id integer;
  v_animal_name text;
  v_animal_icon text;
BEGIN
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  IF v_enclosure.breeding_completes_at IS NULL OR v_enclosure.breeding_completes_at > now() THEN
    RAISE EXCEPTION 'Breeding not complete yet';
  END IF;

  -- Get animal types
  SELECT * INTO v_animal1_type FROM public.animal_types WHERE id = v_enclosure.animal1_id;
  SELECT * INTO v_animal2_type FROM public.animal_types WHERE id = v_enclosure.animal2_id;

  -- Verify both animals are the same type (safety check)
  IF v_animal1_type.id != v_animal2_type.id THEN
    RAISE EXCEPTION 'Cannot breed different animal types';
  END IF;

  -- Calculate result level: min of both parents + 1, capped at 10
  v_result_level := LEAST(
    GREATEST(
      COALESCE(v_enclosure.animal1_level, 0),
      COALESCE(v_enclosure.animal2_level, 0)
    ) + 1,
    10
  );

  -- Calculate item_id for leveled animal: base_item_id = 1000 + (animal_type_id * 100) + level
  -- Example: Chicken (id=1) level 0 = 1101, level 1 = 1102, level 10 = 1111
  v_result_item_id := 1000 + (v_animal1_type.id * 100) + v_result_level;

  v_animal_name := v_animal1_type.name;
  v_animal_icon := v_animal1_type.icon;

  -- Add to inventory as item
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_result_item_id, 1)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + 1;

  -- Reset breeding
  UPDATE public.zoo_enclosures
  SET breeding_started_at = NULL,
      breeding_completes_at = NULL
  WHERE id = p_enclosure_id;

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'animal_name', v_animal_name,
    'animal_icon', v_animal_icon,
    'animal_level', v_result_level,
    'item_id', v_result_item_id
  );
END;
$$;

COMMENT ON FUNCTION public.collect_bred_animal(integer) IS 'Collect a bred animal from an enclosure. Produces a leveled version (+1, +2, etc. up to +10) of the parent animal type.';

-- Helper function to get animal level from item_id
CREATE OR REPLACE FUNCTION public.get_animal_level_from_item_id(p_item_id integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_level integer;
BEGIN
  -- Check if this is a leveled animal item_id (1000+)
  IF p_item_id < 1000 THEN
    RETURN NULL; -- Not a leveled animal
  END IF;

  -- Extract level: item_id = 1000 + (animal_type_id * 100) + level
  -- level = (item_id - 1000) % 100
  v_level := (p_item_id - 1000) % 100;
  
  -- Validate level is between 0 and 10
  IF v_level < 0 OR v_level > 10 THEN
    RETURN NULL;
  END IF;

  RETURN v_level;
END;
$$;

COMMENT ON FUNCTION public.get_animal_level_from_item_id(integer) IS 'Extract animal level from item_id. Returns NULL if not a leveled animal item.';

-- Helper function to get animal type id from item_id
CREATE OR REPLACE FUNCTION public.get_animal_type_id_from_item_id(p_item_id integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_animal_type_id integer;
BEGIN
  -- Check if this is a leveled animal item_id (1000+)
  IF p_item_id < 1000 THEN
    -- Check if it's the old format (30+)
    IF p_item_id >= 30 AND p_item_id < 100 THEN
      RETURN p_item_id - 30; -- Old format: level 0 animal
    END IF;
    RETURN NULL;
  END IF;

  -- Extract animal_type_id: item_id = 1000 + (animal_type_id * 100) + level
  -- animal_type_id = (item_id - 1000 - level) / 100
  -- Since level = (item_id - 1000) % 100, we can simplify:
  v_animal_type_id := (p_item_id - 1000) / 100;
  
  RETURN v_animal_type_id;
END;
$$;

COMMENT ON FUNCTION public.get_animal_type_id_from_item_id(integer) IS 'Extract animal type id from item_id. Supports both old format (30+) and new leveled format (1000+).';

-- Function to place animal from inventory into enclosure
CREATE OR REPLACE FUNCTION public.place_animal_from_inventory(
  p_enclosure_id integer,
  p_item_id integer,
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
  v_inventory_quantity bigint;
  v_rows_affected integer;
BEGIN
  -- Validate slot
  IF p_slot NOT IN (1, 2) THEN
    RAISE EXCEPTION 'Invalid slot: % (must be 1 or 2)', p_slot;
  END IF;

  -- Get animal type and level from item_id
  v_animal_type_id := public.get_animal_type_id_from_item_id(p_item_id);
  v_animal_level := public.get_animal_level_from_item_id(p_item_id);

  IF v_animal_type_id IS NULL THEN
    RAISE EXCEPTION 'Item % is not a valid animal item', p_item_id;
  END IF;

  -- Verify animal type exists
  IF NOT EXISTS (SELECT 1 FROM public.animal_types WHERE id = v_animal_type_id) THEN
    RAISE EXCEPTION 'Animal type % not found', v_animal_type_id;
  END IF;

  -- Check inventory
  SELECT quantity INTO v_inventory_quantity
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_inventory_quantity IS NULL OR v_inventory_quantity < 1 THEN
    RAISE EXCEPTION 'You do not have this animal in your inventory';
  END IF;

  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Check if slot is already occupied
  IF p_slot = 1 AND v_enclosure.animal1_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 1 is already occupied';
  END IF;

  IF p_slot = 2 AND v_enclosure.animal2_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 2 is already occupied';
  END IF;

  -- Remove from inventory
  UPDATE public.inventory
  SET quantity = quantity - 1
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Place animal in enclosure with level
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_id = v_animal_type_id,
        animal1_level = COALESCE(v_animal_level, 0),
        animal1_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 1';
    END IF;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_id = v_animal_type_id,
        animal2_level = COALESCE(v_animal_level, 0),
        animal2_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 2';
    END IF;
  END IF;

  -- Clean up inventory if quantity reaches 0
  DELETE FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id AND quantity <= 0;
END;
$$;

COMMENT ON FUNCTION public.place_animal_from_inventory(integer, integer, integer) IS 'Place an animal from inventory into an enclosure slot. Supports leveled animals.';

