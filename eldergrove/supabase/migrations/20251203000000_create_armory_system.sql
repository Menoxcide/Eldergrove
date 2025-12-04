-- Create armory system for crafting equipment/weapons from mined ore

-- Create armory_recipes table (similar to recipes but for equipment)
CREATE TABLE IF NOT EXISTS public.armory_recipes (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  input jsonb NOT NULL, -- {"iron_ore": 5, "coal": 2}
  output jsonb NOT NULL, -- {"iron_sword": 1} (maps to item_id 30-39)
  minutes integer NOT NULL,
  armory_type text NOT NULL DEFAULT 'basic_forge' -- Type of armory needed
);

-- Create armories table (similar to factories)
CREATE TABLE IF NOT EXISTS public.armories (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  armory_type text NOT NULL,
  level integer NOT NULL DEFAULT 1,
  PRIMARY KEY (player_id, armory_type)
);

-- Create armory_queue table (similar to factory_queue)
CREATE TABLE IF NOT EXISTS public.armory_queue (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  armory_type text NOT NULL,
  recipe_id integer NOT NULL REFERENCES public.armory_recipes(id) ON DELETE CASCADE,
  slot integer NOT NULL CHECK (slot >= 1 AND slot <= 2),
  started_at timestamptz,
  finishes_at timestamptz NOT NULL,
  PRIMARY KEY (player_id, armory_type, slot)
);

-- Enable RLS
ALTER TABLE public.armory_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.armories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.armory_queue ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view armory recipes
CREATE POLICY "Anyone can view armory recipes" ON public.armory_recipes
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view and manage own armories
CREATE POLICY "Players can view own armories" ON public.armories
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own armories" ON public.armories
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own armories" ON public.armories
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own armories" ON public.armories
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Policy: Players can view and manage own armory queue
CREATE POLICY "Players can view own armory queue" ON public.armory_queue
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own armory queue" ON public.armory_queue
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own armory queue" ON public.armory_queue
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own armory queue" ON public.armory_queue
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime for armory_queue
ALTER PUBLICATION supabase_realtime ADD TABLE public.armory_queue;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_armory_queue_player ON public.armory_queue(player_id);
CREATE INDEX IF NOT EXISTS idx_armories_player ON public.armories(player_id);

-- Seed initial armory for new players
CREATE OR REPLACE FUNCTION public.seed_armory_for_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.armories (player_id, armory_type, level)
  VALUES (new.id, 'basic_forge', 1)
  ON CONFLICT (player_id, armory_type) DO NOTHING;
  RETURN new;
END;
$$;

CREATE TRIGGER on_profile_created_armory
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_armory_for_profile();

-- Seed armory recipes (equipment items 30-39)
INSERT INTO public.armory_recipes (name, input, output, minutes, armory_type) VALUES
('Iron Sword', '{"iron_ore": 5, "coal": 2}'::jsonb, '{"iron_sword": 1}'::jsonb, 5, 'basic_forge'),
('Steel Blade', '{"iron_ore": 10, "coal": 5, "copper_ore": 3}'::jsonb, '{"steel_blade": 1}'::jsonb, 10, 'basic_forge'),
('Diamond Armor', '{"crystal_shard": 5, "silver_ore": 3}'::jsonb, '{"diamond_armor": 1}'::jsonb, 15, 'basic_forge'),
('Mithril Sword', '{"mithril_ore": 3, "crystal_shard": 2}'::jsonb, '{"mithril_sword": 1}'::jsonb, 20, 'basic_forge'),
('Aether Blade', '{"aether_crystal": 2, "mithril_ore": 2}'::jsonb, '{"aether_blade": 1}'::jsonb, 30, 'basic_forge'),
('Dragon Scale Armor', '{"dragon_scale": 1, "aether_crystal": 1}'::jsonb, '{"dragon_scale_armor": 1}'::jsonb, 45, 'basic_forge'),
('Ancient Relic Weapon', '{"ancient_relic": 1, "dragon_scale": 1}'::jsonb, '{"ancient_relic_weapon": 1}'::jsonb, 60, 'basic_forge')
ON CONFLICT (name) DO NOTHING;

-- RPC function to start armory crafting
CREATE OR REPLACE FUNCTION public.start_armory_craft(
  p_armory_type text,
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
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
  v_item_id integer;
BEGIN
  -- Validate armory exists
  IF NOT EXISTS (
    SELECT 1 FROM public.armories 
    WHERE player_id = v_player_id 
    AND armory_type = p_armory_type
  ) THEN
    RAISE EXCEPTION 'Armory "%" does not exist for this player', p_armory_type;
  END IF;

  -- Get recipe details
  SELECT * INTO v_recipe 
  FROM public.armory_recipes 
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Check available slots (max 2)
  SELECT count(*) INTO v_slot_count
  FROM public.armory_queue
  WHERE player_id = v_player_id
  AND armory_type = p_armory_type;

  IF v_slot_count >= 2 THEN
    RAISE EXCEPTION 'Armory "%" queue is full (max 2 slots)', p_armory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources from inventory (ore items 20-29)
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input ore name to item_id
    CASE v_input_key
      WHEN 'coal' THEN v_item_id := 20;
      WHEN 'iron_ore' THEN v_item_id := 21;
      WHEN 'copper_ore' THEN v_item_id := 22;
      WHEN 'silver_ore' THEN v_item_id := 23;
      WHEN 'gold_ore' THEN v_item_id := 24;
      WHEN 'crystal_shard' THEN v_item_id := 25;
      WHEN 'mithril_ore' THEN v_item_id := 26;
      WHEN 'aether_crystal' THEN v_item_id := 27;
      WHEN 'dragon_scale' THEN v_item_id := 28;
      WHEN 'ancient_relic' THEN v_item_id := 29;
      ELSE RAISE EXCEPTION 'Unsupported input ore "%"', v_input_key;
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
  INSERT INTO public.armory_queue (
    player_id,
    armory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  ) VALUES (
    v_player_id,
    p_armory_type,
    v_recipe.id,
    v_next_slot,
    now(),
    now() + (v_recipe.minutes * interval '1 minute')
  );
END;
$$;

COMMENT ON FUNCTION public.start_armory_craft(text, text) IS 'Start armory crafting: deducts input ore from inventory, adds to queue (max 2 slots).';

-- RPC function to collect completed armory craft
CREATE OR REPLACE FUNCTION public.collect_armory(p_slot integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_armory_type text;
  v_queue record;
  v_output jsonb;
  v_key text;
  v_qty_str text;
  v_qty integer;
  v_item_id integer;
  v_total_xp integer := 0;
  v_result jsonb;
BEGIN
  -- Fetch queue entry by slot
  SELECT * INTO v_queue
  FROM public.armory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No craft found in slot %', p_slot;
  END IF;

  v_armory_type := v_queue.armory_type;

  IF v_queue.finishes_at > now() THEN
    RAISE EXCEPTION 'Craft in slot % not ready yet (finishes at %)', p_slot, v_queue.finishes_at;
  END IF;

  -- Get recipe output
  SELECT output INTO v_output
  FROM public.armory_recipes
  WHERE id = v_queue.recipe_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe with id % not found', v_queue.recipe_id;
  END IF;

  -- Award output equipment to inventory (equipment items 30-39)
  FOR v_key, v_qty_str IN SELECT key, value FROM jsonb_each_text(v_output) LOOP
    v_qty := v_qty_str::integer;

    -- Map output equipment name to item_id
    CASE v_key
      WHEN 'iron_sword' THEN v_item_id := 30;
      WHEN 'steel_blade' THEN v_item_id := 31;
      WHEN 'diamond_armor' THEN v_item_id := 32;
      WHEN 'mithril_sword' THEN v_item_id := 33;
      WHEN 'aether_blade' THEN v_item_id := 34;
      WHEN 'dragon_scale_armor' THEN v_item_id := 35;
      WHEN 'ancient_relic_weapon' THEN v_item_id := 36;
      ELSE NULL;
    END CASE;

    IF v_item_id IS NOT NULL THEN
      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;

      -- Calculate XP for this equipment
      v_total_xp := v_total_xp + COALESCE(public.get_item_xp(v_item_id, v_qty), 0);
    END IF;
  END LOOP;

  -- Grant XP
  IF v_total_xp > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_total_xp);
  END IF;

  -- Remove queue entry
  DELETE FROM public.armory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress('produce', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'output', v_output,
    'xp_gained', v_total_xp
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.collect_armory(integer) IS 'Collect completed armory craft, adds equipment items to inventory, grants XP. Returns result with output and XP gained.';

-- RPC function to upgrade armory
CREATE OR REPLACE FUNCTION public.upgrade_armory(p_armory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_armory record;
  v_current_level integer;
  v_upgrade_cost integer;
  v_current_crystals bigint;
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
  WHERE id = v_player_id;

  UPDATE public.armories
  SET level = level + 1
  WHERE player_id = v_player_id AND armory_type = p_armory_type;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_current_level + 1,
    'cost', v_upgrade_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_armory(text) IS 'Upgrade an armory to the next level';

-- Initialize armory for existing players
INSERT INTO public.armories (player_id, armory_type, level)
SELECT id, 'basic_forge', 1
FROM public.profiles
ON CONFLICT (player_id, armory_type) DO NOTHING;

