-- Add factory production slot limits with exponential crystal costs
-- First 2 slots are free, then exponential pricing: 500, 1000, 2000, 4000, etc.

-- Add max_factory_slots column to profiles
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'max_factory_slots'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN max_factory_slots integer DEFAULT 2;
  END IF;
END $$;

-- Function to calculate factory slot purchase cost
CREATE OR REPLACE FUNCTION public.get_factory_slot_cost(p_current_max integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- First 2 are free, then exponential: 500 * 2^(current_max - 2)
  IF p_current_max < 2 THEN
    RETURN 0;
  END IF;
  RETURN 500 * POWER(2, p_current_max - 2)::integer;
END;
$$;

COMMENT ON FUNCTION public.get_factory_slot_cost(integer) IS 'Calculate cost for next factory slot. Returns 0 for first 2, then exponential pricing.';

-- Function to purchase additional factory slot
CREATE OR REPLACE FUNCTION public.purchase_factory_slot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_max integer;
  v_cost integer;
  v_current_crystals bigint;
BEGIN
  -- Get current max_factory_slots (defaults to 2 if null)
  SELECT COALESCE(max_factory_slots, 2) INTO v_current_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate cost for next slot
  v_cost := public.get_factory_slot_cost(v_current_max);

  -- Get current crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required % for next factory slot, available %', v_cost, v_current_crystals;
  END IF;

  -- Deduct crystals and increase max_factory_slots
  UPDATE public.profiles
  SET crystals = crystals - v_cost,
      max_factory_slots = max_factory_slots + 1
  WHERE id = v_player_id;

  RETURN jsonb_build_object(
    'success', true,
    'cost_paid', v_cost,
    'new_max_slots', v_current_max + 1
  );
END;
$$;

COMMENT ON FUNCTION public.purchase_factory_slot() IS 'Purchase an additional factory production slot with exponential crystal cost';

-- Function to get factory slot info (for UI display)
CREATE OR REPLACE FUNCTION public.get_factory_slot_info()
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
  -- Get current max_factory_slots (defaults to 2 if null)
  SELECT COALESCE(max_factory_slots, 2) INTO v_current_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Get current active slot count (across all factories)
  SELECT COUNT(*) INTO v_current_count
  FROM public.factory_queue
  WHERE player_id = v_player_id;

  -- Calculate cost for next slot
  v_cost := public.get_factory_slot_cost(v_current_max);

  RETURN jsonb_build_object(
    'current_slots_used', v_current_count,
    'max_slots', v_current_max,
    'next_cost', v_cost,
    'can_add_more', v_current_count < v_current_max
  );
END;
$$;

COMMENT ON FUNCTION public.get_factory_slot_info() IS 'Get information about factory slot limits and costs for current player';

-- Update start_factory_production to use max_factory_slots instead of hardcoded 2
CREATE OR REPLACE FUNCTION public.start_factory_production(
  p_factory_type text,
  p_recipe_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_recipe record;
  v_slot_count integer;
  v_max_slots integer;
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
  v_item_id integer;
BEGIN
  -- Validate factory exists
  IF NOT EXISTS (
    SELECT 1 FROM public.factories 
    WHERE player_id = v_player_id 
    AND factory_type = p_factory_type
  ) THEN
    RAISE EXCEPTION 'Factory "%" does not exist for this player', p_factory_type;
  END IF;

  -- Get recipe details
  SELECT * INTO v_recipe 
  FROM public.recipes 
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Get max slots from profile (global limit shared across all factories)
  SELECT COALESCE(max_factory_slots, 2) INTO v_max_slots
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check available slots against max (count all slots across all factories)
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id;

  IF v_slot_count >= v_max_slots THEN
    RAISE EXCEPTION 'All factory production slots are full (%/% slots used). Purchase more slots to increase capacity.', v_slot_count, v_max_slots;
  END IF;

  -- Calculate next slot number for this specific factory
  SELECT COALESCE(MAX(slot), 0) + 1 INTO v_next_slot
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  -- Validate and deduct input resources from inventory
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id (expanded to handle all crops)
    CASE v_input_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'carrot' THEN v_item_id := 2;
      WHEN 'potato' THEN v_item_id := 3;
      WHEN 'tomato' THEN v_item_id := 4;
      WHEN 'corn' THEN v_item_id := 5;
      WHEN 'pumpkin' THEN v_item_id := 6;
      WHEN 'bread' THEN v_item_id := 8;
      WHEN 'berry' THEN v_item_id := 11;
      WHEN 'herbs' THEN v_item_id := 12;
      WHEN 'magic_mushroom' THEN v_item_id := 13;
      WHEN 'enchanted_flower' THEN v_item_id := 14;
      ELSE RAISE EXCEPTION 'Unsupported input resource "%"', v_input_key;
    END CASE;

    v_current_qty := COALESCE(
      (SELECT quantity FROM public.inventory WHERE player_id = v_player_id AND item_id = v_item_id),
      0
    );

    IF v_current_qty < v_input_qty THEN
      RAISE EXCEPTION 'Insufficient "%": required %, available %', v_input_key, v_input_qty, v_current_qty;
    END IF;

    -- Deduct from inventory
    UPDATE public.inventory SET
      quantity = quantity - v_input_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Insert into queue
  INSERT INTO public.factory_queue (
    player_id,
    factory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  ) VALUES (
    v_player_id,
    p_factory_type,
    v_recipe.id,
    v_next_slot,
    now(),
    now() + (v_recipe.minutes * interval '1 minute')
  );
END;
$$;

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources from inventory, adds to queue. Uses max_factory_slots from profile instead of hardcoded limit.';

