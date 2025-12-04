-- Create zoo/animal system with enclosures, breeding, and passive resource generation

-- Create animal_types table (master list)
CREATE TABLE IF NOT EXISTS public.animal_types (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  rarity text NOT NULL CHECK (rarity IN ('common', 'rare', 'legendary')),
  base_cost_crystals integer NOT NULL DEFAULT 100,
  produces_item_id integer, -- Item produced passively
  produces_quantity integer DEFAULT 1,
  produces_interval_minutes integer DEFAULT 60, -- How often it produces
  breeding_time_minutes integer DEFAULT 30, -- Time to breed
  icon text DEFAULT '🐾',
  description text
);

-- Create zoo_enclosures table
CREATE TABLE IF NOT EXISTS public.zoo_enclosures (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  enclosure_name text NOT NULL,
  animal1_id integer REFERENCES public.animal_types(id) ON DELETE SET NULL,
  animal2_id integer REFERENCES public.animal_types(id) ON DELETE SET NULL,
  animal1_produced_at timestamptz, -- Last production time
  animal2_produced_at timestamptz,
  breeding_started_at timestamptz, -- When breeding started
  breeding_completes_at timestamptz, -- When breeding finishes
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.animal_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zoo_enclosures ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view animal types
DROP POLICY IF EXISTS "Anyone can view animal types" ON public.animal_types;
CREATE POLICY "Anyone can view animal types" ON public.animal_types
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view and manage own enclosures
DROP POLICY IF EXISTS "Players can view own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can view own enclosures" ON public.zoo_enclosures
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can insert own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can insert own enclosures" ON public.zoo_enclosures
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can update own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can update own enclosures" ON public.zoo_enclosures
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can delete own enclosures" ON public.zoo_enclosures
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'zoo_enclosures'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.zoo_enclosures;
  END IF;
END $$;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_zoo_enclosures_player ON public.zoo_enclosures(player_id);

-- Seed animal types
INSERT INTO public.animal_types (name, rarity, base_cost_crystals, produces_item_id, produces_quantity, produces_interval_minutes, breeding_time_minutes, icon, description) VALUES
-- Common animals
('Chicken', 'common', 100, 1, 2, 30, 20, '🐔', 'Produces Wheat every 30 minutes'),
('Cow', 'common', 200, 8, 1, 60, 40, '🐄', 'Produces Herbs every hour'),
('Pig', 'common', 150, 3, 1, 45, 30, '🐷', 'Produces Potatoes every 45 minutes'),
('Sheep', 'common', 180, 7, 1, 50, 35, '🐑', 'Produces Berries every 50 minutes'),
-- Rare animals
('Unicorn', 'rare', 1000, 9, 1, 120, 90, '🦄', 'Produces Magic Mushrooms every 2 hours'),
('Phoenix', 'rare', 1500, 10, 1, 180, 120, '🔥', 'Produces Enchanted Flowers every 3 hours'),
('Dragon', 'rare', 2000, 28, 1, 240, 180, '🐉', 'Produces Dragon Scales every 4 hours'),
-- Legendary animals
('Spirit Wolf', 'legendary', 5000, 27, 1, 360, 240, '🐺', 'Produces Aether Crystals every 6 hours'),
('Ancient Guardian', 'legendary', 10000, 29, 1, 480, 360, '🛡️', 'Produces Ancient Relics every 8 hours')
ON CONFLICT (name) DO NOTHING;

-- Function to create an enclosure
CREATE OR REPLACE FUNCTION public.create_enclosure(p_enclosure_name text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure_id integer;
BEGIN
  INSERT INTO public.zoo_enclosures (player_id, enclosure_name)
  VALUES (v_player_id, p_enclosure_name)
  RETURNING id INTO v_enclosure_id;

  RETURN v_enclosure_id;
END;
$$;

COMMENT ON FUNCTION public.create_enclosure(text) IS 'Create a new empty enclosure';

-- Function to add animal to enclosure
CREATE OR REPLACE FUNCTION public.add_animal_to_enclosure(
  p_enclosure_id integer,
  p_animal_type_id integer,
  p_slot integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

  IF v_current_crystals < v_animal_type.base_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_animal_type.base_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_animal_type.base_cost_crystals
  WHERE id = v_player_id;

  -- Add animal to enclosure
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

COMMENT ON FUNCTION public.add_animal_to_enclosure(integer, integer, integer) IS 'Add an animal to an enclosure slot';

-- Function to collect production from animal
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
  v_produced_at timestamptz;
  v_item_id integer;
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
    v_produced_at := v_enclosure.animal1_produced_at;
  ELSE
    v_animal_id := v_enclosure.animal2_id;
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
  v_quantity := v_animal_type.produces_quantity;
  v_interval_minutes := v_animal_type.produces_interval_minutes;

  -- Check if production is ready
  IF v_produced_at IS NULL OR v_produced_at + (v_interval_minutes || ' minutes')::interval > now() THEN
    RAISE EXCEPTION 'Animal production not ready yet';
  END IF;

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

COMMENT ON FUNCTION public.collect_animal_production(integer, integer) IS 'Collect production from an animal in an enclosure';

-- Function to start breeding
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

  -- Use longer breeding time
  v_breeding_time_minutes := GREATEST(v_animal1_type.breeding_time_minutes, v_animal2_type.breeding_time_minutes);

  -- Start breeding
  UPDATE public.zoo_enclosures
  SET breeding_started_at = now(),
      breeding_completes_at = now() + (v_breeding_time_minutes || ' minutes')::interval
  WHERE id = p_enclosure_id;
END;
$$;

COMMENT ON FUNCTION public.start_breeding(integer) IS 'Start breeding between two animals in an enclosure';

-- Function to collect bred animal
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
  v_result_animal_id integer;
  v_result_animal_type record;
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

  -- Determine result animal (higher rarity, or random if same)
  IF v_animal1_type.rarity = 'legendary' OR v_animal2_type.rarity = 'legendary' THEN
    -- At least one legendary parent = chance for legendary
    IF random() < 0.3 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'legendary' ORDER BY random() LIMIT 1;
    ELSIF random() < 0.6 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSE
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    END IF;
  ELSIF v_animal1_type.rarity = 'rare' OR v_animal2_type.rarity = 'rare' THEN
    -- At least one rare parent
    IF random() < 0.2 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSE
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    END IF;
  ELSE
    -- Both common = common result
    SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
  END IF;

  SELECT * INTO v_result_animal_type FROM public.animal_types WHERE id = v_result_animal_id;

  -- Add to inventory as item (using animal_type id as item_id, or create special item_ids 30+)
  -- For now, we'll add the animal type ID as a special item
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, 30 + v_result_animal_id, 1) -- Use item_ids 30+ for animals
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
    'animal_id', v_result_animal_id,
    'animal_name', v_result_animal_type.name,
    'animal_icon', v_result_animal_type.icon
  );
END;
$$;

COMMENT ON FUNCTION public.collect_bred_animal(integer) IS 'Collect a bred animal from an enclosure';

