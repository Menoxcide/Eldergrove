-- Add level-based storage capacity bonus
-- Base: 50 + (warehouse_level - 1) * 25
-- Bonus: +5 storage per player level

CREATE OR REPLACE FUNCTION public.get_storage_capacity(p_level integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_warehouse_level integer;
BEGIN
  -- This function signature is for warehouse level only
  -- Base: 50, each warehouse level adds 25
  RETURN 50 + (p_level - 1) * 25;
END;
$$;

COMMENT ON FUNCTION public.get_storage_capacity(integer) IS 'Calculate storage capacity from warehouse level (base calculation). Use get_player_storage_capacity for full calculation including player level bonus.';

-- New function that includes player level bonus
CREATE OR REPLACE FUNCTION public.get_player_storage_capacity(p_player_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_warehouse_level integer;
  v_player_level integer;
  v_base_capacity integer;
  v_level_bonus integer;
  v_total_capacity integer;
BEGIN
  -- Get warehouse level (default to 1 if not found)
  SELECT COALESCE(level, 1) INTO v_warehouse_level
  FROM public.warehouse_upgrades
  WHERE player_id = p_player_id;
  
  -- Get player level (default to 1 if not found)
  SELECT COALESCE(level, 1) INTO v_player_level
  FROM public.profiles
  WHERE id = p_player_id;
  
  -- Base capacity: 50 + (warehouse_level - 1) * 25
  v_base_capacity := 50 + (v_warehouse_level - 1) * 25;
  
  -- Level bonus: +5 storage per player level
  v_level_bonus := v_player_level * 5;
  
  -- Total capacity
  v_total_capacity := v_base_capacity + v_level_bonus;
  
  RETURN v_total_capacity;
END;
$$;

COMMENT ON FUNCTION public.get_player_storage_capacity(uuid) IS 'Calculate total storage capacity including warehouse level and player level bonus. Base: 50 + (warehouse_level - 1) * 25, Bonus: +5 per player level.';

-- Update upgrade_warehouse to use new storage calculation
CREATE OR REPLACE FUNCTION public.upgrade_warehouse()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_level integer;
  v_new_level integer;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_new_capacity integer;
  v_result jsonb;
BEGIN
  -- Get current warehouse level
  SELECT COALESCE(level, 1) INTO v_current_level
  FROM public.warehouse_upgrades
  WHERE player_id = v_player_id;

  IF v_current_level >= 10 THEN
    RAISE EXCEPTION 'Warehouse is already at maximum level (10)';
  END IF;

  v_new_level := v_current_level + 1;
  
  -- Calculate upgrade cost (exponential: 100 * level^2)
  v_upgrade_cost := 100 * v_new_level * v_new_level;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_upgrade_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost
  WHERE id = v_player_id;

  -- Update or insert warehouse upgrade
  INSERT INTO public.warehouse_upgrades (player_id, level)
  VALUES (v_player_id, v_new_level)
  ON CONFLICT (player_id) DO UPDATE SET
    level = v_new_level,
    upgraded_at = now();

  -- Update storage capacity using new function that includes player level bonus
  v_new_capacity := public.get_player_storage_capacity(v_player_id);
  UPDATE public.profiles
  SET storage_capacity = v_new_capacity
  WHERE id = v_player_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'new_capacity', v_new_capacity,
    'cost', v_upgrade_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_warehouse() IS 'Upgrade warehouse: increases storage capacity, costs crystals based on level. Capacity includes player level bonus.';

-- Update get_storage_usage to use new storage calculation
CREATE OR REPLACE FUNCTION public.get_storage_usage(p_player_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_capacity integer;
  v_used integer;
  v_result jsonb;
BEGIN
  -- Get capacity using new function that includes player level bonus
  v_capacity := public.get_player_storage_capacity(p_player_id);

  -- Count distinct items (each item type counts as 1 slot)
  SELECT count(DISTINCT item_id) INTO v_used
  FROM public.inventory
  WHERE player_id = p_player_id AND quantity > 0;

  SELECT jsonb_build_object(
    'capacity', v_capacity,
    'used', v_used,
    'available', GREATEST(v_capacity - v_used, 0),
    'percentage', ROUND((v_used::numeric / NULLIF(v_capacity, 0)) * 100, 2)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_storage_usage(uuid) IS 'Get current storage usage statistics for a player. Capacity includes player level bonus.';

