-- Add new_crystal_balance returns to RPC functions that modify crystals
-- This ensures the frontend can update crystal balance without race conditions

-- Update upgrade_armory to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.upgrade_armory(p_armory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_armory record;
  v_current_level integer;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
  v_result jsonb;
BEGIN
  -- Get armory
  SELECT * INTO v_armory
  FROM public.armories
  WHERE player_id = v_player_id AND armory_type = p_armory_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Armory "%" does not exist for this player', p_armory_type;
  END IF;

  v_current_level := v_armory.level;

  IF v_current_level >= 5 THEN
    RAISE EXCEPTION 'Armory "%" is already at maximum level', p_armory_type;
  END IF;

  -- Calculate upgrade cost (similar to factory)
  v_upgrade_cost := 1000 * v_current_level; -- 1000, 2000, 3000, 4000

  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_upgrade_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost, v_current_crystals;
  END IF;

  -- Deduct crystals and upgrade
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost
  WHERE id = v_player_id
  RETURNING crystals INTO v_new_crystals;

  UPDATE public.armories
  SET level = level + 1
  WHERE player_id = v_player_id AND armory_type = p_armory_type;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_current_level + 1,
    'cost', v_upgrade_cost,
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_armory(text) IS 'Upgrade an armory to the next level. Returns new level, cost, and new crystal balance.';

-- Update purchase_factory_slot to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.purchase_factory_slot()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_max integer;
  v_cost integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
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
  WHERE id = v_player_id
  RETURNING crystals INTO v_new_crystals;

  RETURN jsonb_build_object(
    'success', true,
    'cost_paid', v_cost,
    'new_max_slots', v_current_max + 1,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.purchase_factory_slot() IS 'Purchase an additional factory production slot with exponential crystal cost. Returns cost paid, new max slots, and new crystal balance.';

-- Update upgrade_factory to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.upgrade_factory(p_factory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory record;
  v_upgrade_cost record;
  v_current_level integer;
  v_new_level integer;
  v_base_cost_crystals integer;
  v_discount_percent numeric;
  v_discount_amount integer;
  v_cost_crystals integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
  v_result jsonb;
BEGIN
  -- Get factory
  SELECT * INTO v_factory
  FROM public.factories
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factory "%" not found for this player', p_factory_type;
  END IF;

  v_current_level := v_factory.level;

  IF v_current_level >= 5 THEN
    RAISE EXCEPTION 'Factory "%" is already at maximum level (5)', p_factory_type;
  END IF;

  v_new_level := v_current_level + 1;

  -- Get upgrade cost
  SELECT * INTO v_upgrade_cost
  FROM public.building_upgrade_costs
  WHERE building_type = p_factory_type
    AND from_level = v_current_level
    AND to_level = v_new_level;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upgrade cost not found for % level % to %', p_factory_type, v_current_level, v_new_level;
  END IF;

  v_base_cost_crystals := v_upgrade_cost.cost_crystals;

  -- Get level discount
  v_discount_percent := public.get_level_discount(v_player_id);
  v_discount_amount := FLOOR(v_base_cost_crystals * v_discount_percent);
  v_cost_crystals := v_base_cost_crystals - v_discount_amount;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals (with discount applied)
  UPDATE public.profiles
  SET crystals = crystals - v_cost_crystals
  WHERE id = v_player_id
  RETURNING crystals INTO v_new_crystals;

  -- Upgrade factory
  UPDATE public.factories
  SET level = v_new_level
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'cost_crystals', v_cost_crystals,
    'discount_applied', v_discount_amount,
    'unlocks_queue_slot', COALESCE(v_upgrade_cost.unlocks_queue_slot, false),
    'speed_multiplier', v_upgrade_cost.production_speed_multiplier,
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_factory(text) IS 'Upgrade a factory to the next level. Returns new level, cost, discount, unlocks, speed multiplier, and new crystal balance.';

-- Update repair_tool to return new_crystal_balance
DROP FUNCTION IF EXISTS public.repair_tool(text);
CREATE FUNCTION public.repair_tool(p_tool_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_tool record;
  v_repair_cost integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
BEGIN
  SELECT * INTO v_tool
  FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tool "%" not found', p_tool_type;
  END IF;

  IF v_tool.durability >= 100 THEN
    RAISE EXCEPTION 'Tool "%" is already at full durability', p_tool_type;
  END IF;

  -- Repair cost: 10 crystals per durability point
  v_repair_cost := (100 - v_tool.durability) * 10;

  -- Get current crystals with row-level lock to prevent race conditions
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player profile not found';
  END IF;

  -- Check for NULL crystals (shouldn't happen, but be safe)
  IF v_current_crystals IS NULL THEN
    v_current_crystals := 0;
  END IF;

  IF v_current_crystals < v_repair_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_repair_cost, v_current_crystals;
  END IF;

  -- Deduct crystals and repair (using the locked row)
  UPDATE public.profiles
  SET crystals = COALESCE(crystals, 0) - v_repair_cost
  WHERE id = v_player_id
  RETURNING crystals INTO v_new_crystals;

  -- Verify the deduction succeeded
  IF v_new_crystals IS NULL OR v_new_crystals < 0 THEN
    RAISE EXCEPTION 'Failed to deduct crystals. Transaction rolled back.';
  END IF;

  UPDATE public.mining_tools
  SET durability = 100
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  RETURN jsonb_build_object(
    'success', true,
    'repair_cost', v_repair_cost,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.repair_tool(text) IS 'Repair a mining tool to full durability. Returns repair cost and new crystal balance.';

-- Update upgrade_mining_tool to return new_crystal_balance
DROP FUNCTION IF EXISTS public.upgrade_mining_tool(text);
CREATE FUNCTION public.upgrade_mining_tool(p_tool_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_tool record;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_next_tool text;
  v_new_crystals bigint;
BEGIN
  -- Get tool
  SELECT * INTO v_tool
  FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tool "%" not found', p_tool_type;
  END IF;

  -- Determine next tool
  CASE p_tool_type
    WHEN 'basic_pickaxe' THEN v_next_tool := 'iron_pickaxe';
    WHEN 'iron_pickaxe' THEN v_next_tool := 'diamond_pickaxe';
    WHEN 'diamond_pickaxe' THEN v_next_tool := 'magic_pickaxe';
    ELSE
      RAISE EXCEPTION 'Tool "%" is already at maximum level', p_tool_type;
  END CASE;

  -- Upgrade cost
  CASE p_tool_type
    WHEN 'basic_pickaxe' THEN v_upgrade_cost := 500;
    WHEN 'iron_pickaxe' THEN v_upgrade_cost := 2000;
    WHEN 'diamond_pickaxe' THEN v_upgrade_cost := 5000;
    ELSE v_upgrade_cost := 0;
  END CASE;

  -- Get current crystals with row-level lock to prevent race conditions
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player profile not found';
  END IF;

  -- Check for NULL crystals (shouldn't happen, but be safe)
  IF v_current_crystals IS NULL THEN
    v_current_crystals := 0;
  END IF;

  -- Check if player has enough crystals
  IF v_current_crystals < v_upgrade_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost, v_current_crystals;
  END IF;

  -- Deduct crystals atomically (using the locked row)
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost
  WHERE id = v_player_id
  RETURNING crystals INTO v_new_crystals;

  -- Verify the deduction succeeded
  IF v_new_crystals IS NULL OR v_new_crystals < 0 THEN
    RAISE EXCEPTION 'Failed to deduct crystals. Transaction rolled back.';
  END IF;

  -- Create new tool and delete old
  INSERT INTO public.mining_tools (player_id, tool_type, level, durability)
  VALUES (v_player_id, v_next_tool, 1, 100)
  ON CONFLICT (player_id, tool_type) DO UPDATE SET
    level = 1,
    durability = 100;

  DELETE FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  RETURN jsonb_build_object(
    'success', true,
    'upgrade_cost', v_upgrade_cost,
    'new_tool_type', v_next_tool,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.upgrade_mining_tool(text) IS 'Upgrade a mining tool to the next tier. Returns upgrade cost, new tool type, and new crystal balance.';

-- Update purchase_premium_item to return new_crystal_balance and new_aether_balance
CREATE OR REPLACE FUNCTION public.purchase_premium_item(
  p_item_id text,
  p_use_aether boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_item record;
  v_current_aether integer;
  v_current_crystals bigint;
  v_new_aether integer;
  v_new_crystals bigint;
  v_cost integer;
  v_result jsonb;
  v_minutes integer;
BEGIN
  -- Get item
  SELECT * INTO v_item
  FROM public.premium_shop
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % not found or not available', p_item_id;
  END IF;

  -- Determine cost
  IF p_use_aether THEN
    v_cost := v_item.cost_aether;
    
    -- Check aether
    SELECT COALESCE(aether, 0) INTO v_current_aether
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_aether < v_cost THEN
      RAISE EXCEPTION 'Insufficient aether: required %, available %', v_cost, v_current_aether;
    END IF;

    -- Deduct aether
    UPDATE public.profiles
    SET aether = aether - v_cost
    WHERE id = v_player_id
    RETURNING aether INTO v_new_aether;

    -- Record transaction
    INSERT INTO public.aether_transactions (player_id, transaction_type, amount, description, metadata)
    VALUES (v_player_id, 'spent', v_cost, 'Purchased ' || v_item.name, jsonb_build_object('item_id', p_item_id));
  ELSE
    v_cost := v_item.cost_crystals;
    
    IF v_cost <= 0 THEN
      RAISE EXCEPTION 'Item cannot be purchased with crystals';
    END IF;

    -- Check crystals
    SELECT crystals INTO v_current_crystals
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_crystals < v_cost THEN
      RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
    END IF;

    -- Deduct crystals
    UPDATE public.profiles
    SET crystals = crystals - v_cost
    WHERE id = v_player_id
    RETURNING crystals INTO v_new_crystals;
  END IF;

  -- Apply item effects based on type
  CASE v_item.item_type
    WHEN 'speed_up' THEN
      v_minutes := (v_item.metadata->>'minutes')::integer;
      -- Speed-ups are applied manually by player, just return the minutes available
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'speed_up',
        'minutes', v_minutes,
        'message', 'Speed-up added to inventory. Use it from factory or farm pages.'
      );
      
    WHEN 'decoration' THEN
      -- Decoration would be added to inventory or placed directly
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'decoration',
        'decoration_type', v_item.metadata->>'decoration_type',
        'message', 'Decoration unlocked! Place it from the town map.'
      );
      
    WHEN 'building' THEN
      -- Building would be unlocked or placed
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'building',
        'building_type', v_item.metadata->>'building_type',
        'message', 'Premium building unlocked!'
      );
      
    WHEN 'boost' THEN
      -- Boost would be activated
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'boost',
        'duration_hours', (v_item.metadata->>'duration_hours')::integer,
        'metadata', v_item.metadata,
        'message', 'Boost activated!'
      );
      
    WHEN 'bundle' THEN
      -- Bundle items would be awarded
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'bundle',
        'message', 'Bundle items added to your inventory!'
      );
      
    ELSE
      RAISE EXCEPTION 'Unknown item type: %', v_item.item_type;
  END CASE;

  -- Add balance information to result
  IF p_use_aether THEN
    v_result := v_result || jsonb_build_object('new_aether_balance', v_new_aether);
  ELSE
    v_result := v_result || jsonb_build_object('new_crystal_balance', v_new_crystals);
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_premium_item(text, boolean) IS 'Purchase a premium shop item. Returns success, item type, item-specific data, and new crystal/aether balance.';

