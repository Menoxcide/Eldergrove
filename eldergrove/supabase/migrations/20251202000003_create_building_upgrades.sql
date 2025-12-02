-- Create building upgrade system for factories and buildings

-- Ensure factories table has level column (it should already exist)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'factories' AND column_name = 'level'
  ) THEN
    ALTER TABLE public.factories ADD COLUMN level integer DEFAULT 1 CHECK (level >= 1 AND level <= 5);
  END IF;
END $$;

-- Create building_upgrade_costs table for upgrade requirements
CREATE TABLE IF NOT EXISTS public.building_upgrade_costs (
  building_type text NOT NULL,
  from_level integer NOT NULL CHECK (from_level >= 1 AND from_level < 5),
  to_level integer NOT NULL CHECK (to_level > from_level AND to_level <= 5),
  cost_crystals integer NOT NULL,
  cost_materials jsonb, -- {item_id: quantity} format
  unlocks_queue_slot boolean DEFAULT false,
  production_speed_multiplier numeric DEFAULT 1.0,
  PRIMARY KEY (building_type, from_level, to_level)
);

-- Seed upgrade costs for factories
INSERT INTO public.building_upgrade_costs (building_type, from_level, to_level, cost_crystals, cost_materials, unlocks_queue_slot, production_speed_multiplier) VALUES
-- Rune Bakery upgrades
('rune_bakery', 1, 2, 500, '{"8": 5}'::jsonb, true, 0.9), -- Unlocks slot 3, 10% faster
('rune_bakery', 2, 3, 1000, '{"8": 10}'::jsonb, false, 0.8), -- 20% faster
('rune_bakery', 3, 4, 2000, '{"8": 20}'::jsonb, true, 0.7), -- Unlocks slot 4, 30% faster
('rune_bakery', 4, 5, 5000, '{"8": 50}'::jsonb, false, 0.6), -- 40% faster
-- Potion Workshop upgrades
('potion_workshop', 1, 2, 1000, '{"7": 5}'::jsonb, true, 0.9),
('potion_workshop', 2, 3, 2000, '{"7": 10}'::jsonb, false, 0.8),
('potion_workshop', 3, 4, 4000, '{"7": 20}'::jsonb, true, 0.7),
('potion_workshop', 4, 5, 10000, '{"7": 50}'::jsonb, false, 0.6),
-- Enchanting Lab upgrades
('enchanting_lab', 1, 2, 1500, '{"9": 5}'::jsonb, true, 0.9),
('enchanting_lab', 2, 3, 3000, '{"9": 10}'::jsonb, false, 0.8),
('enchanting_lab', 3, 4, 6000, '{"9": 20}'::jsonb, true, 0.7),
('enchanting_lab', 4, 5, 15000, '{"9": 50}'::jsonb, false, 0.6),
-- Kitchen upgrades
('kitchen', 1, 2, 800, '{"8": 5}'::jsonb, true, 0.9),
('kitchen', 2, 3, 1600, '{"8": 10}'::jsonb, false, 0.8),
('kitchen', 3, 4, 3200, '{"8": 20}'::jsonb, true, 0.7),
('kitchen', 4, 5, 8000, '{"8": 50}'::jsonb, false, 0.6)
ON CONFLICT (building_type, from_level, to_level) DO NOTHING;

-- RPC function to upgrade a factory/building
CREATE OR REPLACE FUNCTION public.upgrade_factory(p_factory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory record;
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

  -- Get upgrade cost
  SELECT * INTO v_upgrade_cost
  FROM public.building_upgrade_costs
  WHERE building_type = p_factory_type
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

COMMENT ON FUNCTION public.upgrade_factory(text) IS 'Upgrade a factory: increases level, may unlock queue slots and improve production speed';

-- RPC function to upgrade a building (for non-factory buildings)
CREATE OR REPLACE FUNCTION public.upgrade_building(p_building_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_type_info record;
  v_current_level integer;
  v_new_level integer;
  v_cost_crystals integer;
  v_current_crystals bigint;
  v_result jsonb;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  v_current_level := v_building.level;

  -- Get building type info
  SELECT * INTO v_building_type_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  IF v_current_level >= v_building_type_info.max_level THEN
    RAISE EXCEPTION 'Building is already at maximum level (%)', v_building_type_info.max_level;
  END IF;

  v_new_level := v_current_level + 1;
  
  -- Calculate upgrade cost (base_cost * level)
  v_cost_crystals := v_building_type_info.base_cost_crystals * v_new_level;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost_crystals
  WHERE id = v_player_id;

  -- Upgrade building
  UPDATE public.buildings
  SET level = v_new_level
  WHERE id = p_building_id;

  -- Update population if community building
  IF v_building_type_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = COALESCE(population, 0) + v_building_type_info.provides_population
    WHERE id = v_player_id;
  END IF;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'cost_crystals', v_cost_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_building(integer) IS 'Upgrade a building: increases level, may provide additional population';

