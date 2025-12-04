-- Fix upgrade_factory function to handle factory_type name mapping
-- Factories table uses display names (e.g., "Rune Bakery") but building_upgrade_costs uses keys (e.g., "rune_bakery")
-- This migration updates the function to normalize the factory_type by looking up building_types table

CREATE OR REPLACE FUNCTION public.upgrade_factory(p_factory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory record;
  v_building_type_key text;
  v_upgrade_cost record;
  v_current_crystals bigint;
  v_current_qty bigint;
  v_item_id integer;
  v_required_qty integer;
  v_key text;
  v_value text;
  v_new_level integer;
  v_result jsonb;
BEGIN
  -- Get factory
  SELECT * INTO v_factory
  FROM public.factories
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factory "%" not found for this player', p_factory_type;
  END IF;

  IF v_factory.level >= 5 THEN
    RAISE EXCEPTION 'Factory "%" is already at maximum level (5)', p_factory_type;
  END IF;

  v_new_level := v_factory.level + 1;

  -- Normalize factory_type: convert display name (e.g., "Rune Bakery") to building_type key (e.g., "rune_bakery")
  -- First try direct match (in case it's already normalized)
  SELECT building_type INTO v_building_type_key
  FROM public.building_types
  WHERE building_type = p_factory_type OR name = p_factory_type
  LIMIT 1;

  -- If not found in building_types, try to match by converting the name
  -- This handles cases where factory_type might be stored differently
  IF v_building_type_key IS NULL THEN
    -- Try matching by name (case-insensitive)
    SELECT building_type INTO v_building_type_key
    FROM public.building_types
    WHERE LOWER(name) = LOWER(p_factory_type)
    LIMIT 1;
  END IF;

  -- If still not found, use the original value (for backwards compatibility)
  IF v_building_type_key IS NULL THEN
    v_building_type_key := p_factory_type;
  END IF;

  -- Get upgrade cost using normalized building_type key
  SELECT * INTO v_upgrade_cost
  FROM public.building_upgrade_costs
  WHERE building_type = v_building_type_key
    AND from_level = v_factory.level
    AND to_level = v_new_level;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upgrade path not found for % level % to %', p_factory_type, v_factory.level, v_new_level;
  END IF;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_upgrade_cost.cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost.cost_crystals, v_current_crystals;
  END IF;

  -- Check and deduct materials if required
  IF v_upgrade_cost.cost_materials IS NOT NULL THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_upgrade_cost.cost_materials) LOOP
      v_item_id := v_key::integer;
      v_required_qty := v_value::integer;

      SELECT COALESCE(quantity, 0) INTO v_current_qty
      FROM public.inventory
      WHERE player_id = v_player_id AND item_id = v_item_id;

      IF v_current_qty < v_required_qty THEN
        RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
      END IF;

      -- Deduct from inventory
      UPDATE public.inventory
      SET quantity = quantity - v_required_qty
      WHERE player_id = v_player_id AND item_id = v_item_id;
    END LOOP;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost.cost_crystals
  WHERE id = v_player_id;

  -- Upgrade factory
  UPDATE public.factories
  SET level = v_new_level
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'cost_crystals', v_upgrade_cost.cost_crystals,
    'unlocks_queue_slot', COALESCE(v_upgrade_cost.unlocks_queue_slot, false),
    'speed_multiplier', v_upgrade_cost.production_speed_multiplier
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_factory(text) IS 'Upgrade a factory: increases level, may unlock queue slots and improve production speed. Handles factory_type name mapping between display names and database keys.';

