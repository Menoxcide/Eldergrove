-- Create mining system with dig mechanics, tools, and ore types

-- Create ore_types table (master list of ores)
CREATE TABLE IF NOT EXISTS public.ore_types (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  item_id integer NOT NULL UNIQUE, -- Maps to inventory item_id
  rarity text NOT NULL CHECK (rarity IN ('common', 'rare', 'epic')),
  base_value_crystals integer NOT NULL DEFAULT 0,
  icon text DEFAULT '💎'
);

-- Create mining_tools table (player tools)
CREATE TABLE IF NOT EXISTS public.mining_tools (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tool_type text NOT NULL CHECK (tool_type IN ('basic_pickaxe', 'iron_pickaxe', 'diamond_pickaxe', 'magic_pickaxe')),
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 5),
  durability integer NOT NULL DEFAULT 100 CHECK (durability >= 0 AND durability <= 100),
  created_at timestamptz DEFAULT now(),
  UNIQUE(player_id, tool_type)
);

-- Create mine_digs table (dig history and current state)
CREATE TABLE IF NOT EXISTS public.mine_digs (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  depth integer NOT NULL DEFAULT 0 CHECK (depth >= 0),
  last_dig_at timestamptz DEFAULT now(),
  total_digs integer NOT NULL DEFAULT 0,
  artifacts jsonb DEFAULT '[]'::jsonb, -- Array of found items
  energy_used_today integer DEFAULT 0,
  last_energy_reset timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ore_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mining_tools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mine_digs ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view ore types
CREATE POLICY "Anyone can view ore types" ON public.ore_types
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view and manage own tools
CREATE POLICY "Players can view own tools" ON public.mining_tools
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own tools" ON public.mining_tools
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own tools" ON public.mining_tools
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Policy: Players can view and manage own digs
CREATE POLICY "Players can view own digs" ON public.mine_digs
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own digs" ON public.mine_digs
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own digs" ON public.mine_digs
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.mine_digs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.mining_tools;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_mine_digs_player ON public.mine_digs(player_id);
CREATE INDEX IF NOT EXISTS idx_mining_tools_player ON public.mining_tools(player_id);

-- Seed ore types (using item_ids 20-29 for ores)
INSERT INTO public.ore_types (name, item_id, rarity, base_value_crystals, icon) VALUES
('Coal', 20, 'common', 5, '⚫'),
('Iron Ore', 21, 'common', 10, '🔩'),
('Copper Ore', 22, 'common', 8, '🟠'),
('Silver Ore', 23, 'rare', 25, '⚪'),
('Gold Ore', 24, 'rare', 50, '🟡'),
('Crystal Shard', 25, 'rare', 30, '💎'),
('Mithril Ore', 26, 'epic', 100, '🔷'),
('Aether Crystal', 27, 'epic', 200, '✨'),
('Dragon Scale', 28, 'epic', 500, '🐉'),
('Ancient Relic', 29, 'epic', 1000, '🏺')
ON CONFLICT (name) DO NOTHING;

-- Function to initialize mining for new players
CREATE OR REPLACE FUNCTION public.initialize_mining(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Create basic pickaxe
  INSERT INTO public.mining_tools (player_id, tool_type, level, durability)
  VALUES (p_player_id, 'basic_pickaxe', 1, 100)
  ON CONFLICT (player_id, tool_type) DO NOTHING;

  -- Create mine_digs entry
  INSERT INTO public.mine_digs (player_id, depth, total_digs, energy_used_today, last_energy_reset)
  VALUES (p_player_id, 0, 0, 0, now())
  ON CONFLICT DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.initialize_mining(uuid) IS 'Initialize mining system for a new player';

-- Function to reset daily energy
CREATE OR REPLACE FUNCTION public.reset_mining_energy()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.mine_digs
  SET energy_used_today = 0,
      last_energy_reset = now()
  WHERE last_energy_reset < now() - interval '24 hours';
END;
$$;

COMMENT ON FUNCTION public.reset_mining_energy() IS 'Reset daily mining energy for all players';

-- Function to get energy cost for a dig
CREATE OR REPLACE FUNCTION public.get_dig_energy_cost(p_tool_type text, p_depth integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Base cost increases with depth, better tools reduce cost
  CASE p_tool_type
    WHEN 'basic_pickaxe' THEN RETURN 10 + (p_depth / 10);
    WHEN 'iron_pickaxe' THEN RETURN 8 + (p_depth / 15);
    WHEN 'diamond_pickaxe' THEN RETURN 5 + (p_depth / 20);
    WHEN 'magic_pickaxe' THEN RETURN 3 + (p_depth / 30);
    ELSE RETURN 10;
  END CASE;
END;
$$;

COMMENT ON FUNCTION public.get_dig_energy_cost(text, integer) IS 'Calculate energy cost for a dig based on tool and depth';

-- Function to determine ore drop based on depth and tool
CREATE OR REPLACE FUNCTION public.get_ore_drop(p_depth integer, p_tool_type text)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_roll numeric;
  v_ore_id integer;
BEGIN
  -- Random roll (0-100)
  v_roll := random() * 100;

  -- Drop rates based on depth and tool
  -- Deeper = better ores, better tools = better rates
  IF p_depth < 10 THEN
    -- Surface: Common ores only
    IF v_roll < 50 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    ELSE
      RETURN NULL; -- No ore
    END IF;
  ELSIF p_depth < 30 THEN
    -- Shallow: Common + Rare
    IF v_roll < 40 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    ELSIF v_roll < 60 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSE
      RETURN NULL;
    END IF;
  ELSIF p_depth < 60 THEN
    -- Medium: Rare + Epic
    IF v_roll < 30 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSIF v_roll < 50 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'epic' ORDER BY random() LIMIT 1;
    ELSE
      RETURN NULL;
    END IF;
  ELSE
    -- Deep: Mostly Epic
    IF v_roll < 20 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSIF v_roll < 70 THEN
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'epic' ORDER BY random() LIMIT 1;
    ELSE
      RETURN NULL;
    END IF;
  END IF;

  -- Tool bonus: Better tools increase drop rates
  IF p_tool_type IN ('diamond_pickaxe', 'magic_pickaxe') THEN
    IF random() < 0.1 THEN -- 10% bonus chance
      SELECT item_id INTO v_ore_id FROM public.ore_types WHERE rarity = 'epic' ORDER BY random() LIMIT 1;
    END IF;
  END IF;

  RETURN v_ore_id;
END;
$$;

COMMENT ON FUNCTION public.get_ore_drop(integer, text) IS 'Determine which ore drops based on depth and tool';

-- Function to mine ore
CREATE OR REPLACE FUNCTION public.mine_ore(p_tool_type text DEFAULT 'basic_pickaxe')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_mine_dig record;
  v_tool record;
  v_energy_cost integer;
  v_current_energy integer;
  v_max_energy integer := 100;
  v_ore_id integer;
  v_ore_type record;
  v_new_depth integer;
  v_result jsonb;
BEGIN
  -- Get or create mine_digs entry
  SELECT * INTO v_mine_dig
  FROM public.mine_digs
  WHERE player_id = v_player_id;

  IF NOT FOUND THEN
    PERFORM public.initialize_mining(v_player_id);
    SELECT * INTO v_mine_dig
    FROM public.mine_digs
    WHERE player_id = v_player_id;
  END IF;

  -- Reset energy if needed
  IF v_mine_dig.last_energy_reset < now() - interval '24 hours' THEN
    UPDATE public.mine_digs
    SET energy_used_today = 0, last_energy_reset = now()
    WHERE player_id = v_player_id;
    v_mine_dig.energy_used_today := 0;
  END IF;

  -- Get tool
  SELECT * INTO v_tool
  FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tool "%" not found. Please acquire a basic pickaxe first.', p_tool_type;
  END IF;

  IF v_tool.durability <= 0 THEN
    RAISE EXCEPTION 'Tool "%" is broken. Please repair it.', p_tool_type;
  END IF;

  -- Calculate energy cost
  v_energy_cost := public.get_dig_energy_cost(p_tool_type, v_mine_dig.depth);
  v_current_energy := v_max_energy - v_mine_dig.energy_used_today;

  IF v_current_energy < v_energy_cost THEN
    RAISE EXCEPTION 'Insufficient energy: required %, available %', v_energy_cost, v_current_energy;
  END IF;

  -- Determine ore drop
  v_ore_id := public.get_ore_drop(v_mine_dig.depth, p_tool_type);

  -- Update energy
  UPDATE public.mine_digs
  SET energy_used_today = energy_used_today + v_energy_cost,
      total_digs = total_digs + 1,
      depth = depth + 1,
      last_dig_at = now()
  WHERE player_id = v_player_id;

  -- Reduce tool durability
  UPDATE public.mining_tools
  SET durability = GREATEST(durability - 1, 0)
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  -- Award ore if found
  IF v_ore_id IS NOT NULL THEN
    SELECT * INTO v_ore_type FROM public.ore_types WHERE item_id = v_ore_id;
    
    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_ore_id, 1)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + 1;

    -- Update artifacts JSONB
    UPDATE public.mine_digs
    SET artifacts = artifacts || jsonb_build_array(jsonb_build_object(
      'item_id', v_ore_id,
      'name', v_ore_type.name,
      'found_at', now(),
      'depth', v_mine_dig.depth + 1
    ))
    WHERE player_id = v_player_id;
  END IF;

  -- Check achievements
  PERFORM public.check_achievements('mine_count', 1);

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'mine', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'ore_found', v_ore_id IS NOT NULL,
    'ore_id', v_ore_id,
    'ore_name', CASE WHEN v_ore_id IS NOT NULL THEN v_ore_type.name ELSE NULL END,
    'new_depth', v_mine_dig.depth + 1,
    'energy_remaining', v_max_energy - (v_mine_dig.energy_used_today + v_energy_cost),
    'tool_durability', GREATEST(v_tool.durability - 1, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.mine_ore(text) IS 'Mine ore: consumes energy, reduces tool durability, may find ores based on depth and tool';

-- Function to repair tool
CREATE OR REPLACE FUNCTION public.repair_tool(p_tool_type text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_tool record;
  v_repair_cost integer;
  v_current_crystals bigint;
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

  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_repair_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_repair_cost, v_current_crystals;
  END IF;

  -- Deduct crystals and repair
  UPDATE public.profiles
  SET crystals = crystals - v_repair_cost
  WHERE id = v_player_id;

  UPDATE public.mining_tools
  SET durability = 100
  WHERE player_id = v_player_id AND tool_type = p_tool_type;
END;
$$;

COMMENT ON FUNCTION public.repair_tool(text) IS 'Repair a mining tool to full durability';

-- Function to upgrade tool
CREATE OR REPLACE FUNCTION public.upgrade_mining_tool(p_tool_type text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_tool record;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_next_tool text;
BEGIN
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

  -- Create new tool and delete old
  INSERT INTO public.mining_tools (player_id, tool_type, level, durability)
  VALUES (v_player_id, v_next_tool, 1, 100)
  ON CONFLICT (player_id, tool_type) DO UPDATE SET
    level = 1,
    durability = 100;

  DELETE FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;
END;
$$;

COMMENT ON FUNCTION public.upgrade_mining_tool(text) IS 'Upgrade a mining tool to the next tier';

-- Initialize mining for existing players
INSERT INTO public.mining_tools (player_id, tool_type, level, durability)
SELECT id, 'basic_pickaxe', 1, 100
FROM public.profiles
ON CONFLICT (player_id, tool_type) DO NOTHING;

INSERT INTO public.mine_digs (player_id, depth, total_digs, energy_used_today, last_energy_reset)
SELECT id, 0, 0, 0, now()
FROM public.profiles
ON CONFLICT DO NOTHING;

