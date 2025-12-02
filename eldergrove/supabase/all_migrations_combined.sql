create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  crystals bigint default 500,
  level integer default 1,
  xp bigint default 0,
  created_at timestamptz default now()
);
-- Enable Row Level Security (RLS) on profiles table
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policy for SELECT: Users can view their own profile
CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT
  USING ( auth.uid() = id );

-- Policy for UPDATE: Users can update their own profile
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE
  USING ( auth.uid() = id );
-- handle new user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
  begin
    insert into public.profiles (id)
    values (new.id);
    return new;
  end;
$$;

-- trigger the function on insert
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
-- Create the crops table for the farming system
create table public.crops (
  id serial primary key,
  name text unique not null,
  grow_minutes integer not null,
  yield_crystals integer not null
);

-- Seed initial crops
insert into public.crops (name, grow_minutes, yield_crystals) values
('Wheat', 2, 10),
('Carrot', 5, 25);
-- Create the farm_plots table for the farming system
create table public.farm_plots (
  player_id uuid not null references public.profiles(id) on delete cascade,
  plot_index integer not null,
  crop_id integer references public.crops(id),
  planted_at timestamptz,
  ready_at timestamptz,
  primary key (player_id, plot_index)
);
-- Seed 6 empty farm plots after profile creation

create or replace function public.seed_farm_plots_for_profile()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.farm_plots (player_id, plot_index)
  select new.id, generate_series(1,6);
  return new;
end;
$$;

-- trigger the function on insert
create trigger on_profile_created
  after insert on public.profiles
  for each row
  execute function public.seed_farm_plots_for_profile();
-- Enable RLS on crops table (shared reference data)
ALTER TABLE public.crops
  ENABLE ROW LEVEL SECURITY;

-- Policy: All authenticated users can read crops
DROP POLICY IF EXISTS "Enable read access for authenticated users on crops" ON public.crops;
CREATE POLICY "Enable read access for authenticated users on crops"
  ON public.crops
  FOR SELECT
  TO authenticated
  USING (true);

-- Enable RLS on farm_plots table
ALTER TABLE public.farm_plots
  ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own farm plots
DROP POLICY IF EXISTS "Users view own farm plots" ON public.farm_plots;
CREATE POLICY "Users view own farm plots"
  ON public.farm_plots
  FOR SELECT
  TO authenticated
  USING (player_id = auth.uid());

-- Policy: Users can insert their own farm plots
DROP POLICY IF EXISTS "Users insert own farm plots" ON public.farm_plots;
CREATE POLICY "Users insert own farm plots"
  ON public.farm_plots
  FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can update their own farm plots
DROP POLICY IF EXISTS "Users update own farm plots" ON public.farm_plots;
CREATE POLICY "Users update own farm plots"
  ON public.farm_plots
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can delete their own farm plots
DROP POLICY IF EXISTS "Users delete own farm plots" ON public.farm_plots;
CREATE POLICY "Users delete own farm plots"
  ON public.farm_plots
  FOR DELETE
  TO authenticated
  USING (player_id = auth.uid());
-- Create RPC function to plant a crop on an empty farm plot

create or replace function public.plant_crop(p_plot_index integer, p_crop_id integer)
returns void
language plpgsql
security definer
as $$
declare
  v_grow_minutes integer;
begin
  -- Fetch crop growth time
  select grow_minutes into v_grow_minutes
  from public.crops
  where id = p_crop_id;

  if not found then
    raise exception 'Crop with id % does not exist', p_crop_id;
  end if;

  -- Update only if plot is empty
  update public.farm_plots 
  set 
    crop_id = p_crop_id,
    planted_at = now(),
    ready_at = now() + (v_grow_minutes * interval '1 minute')
  where player_id = auth.uid()
    and plot_index = p_plot_index
    and crop_id is null;

  if not found then
    raise exception 'Cannot plant on plot %: it is not empty or does not exist for this user', p_plot_index;
  end if;

end;
$$;

comment on function public.plant_crop(integer, integer) is 'Plant a crop on an empty farm plot';
-- Create RPC function to harvest a ready crop from a farm plot, add crystals to player, and clear plot

create or replace function public.harvest_plot(p_plot_index integer)
returns bigint
language plpgsql
security definer
as $$
declare
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_crystals integer;
  v_new_crystals bigint;
begin
  -- Fetch current plot crop info
  select crop_id, ready_at into v_crop_id, v_ready_at
  from public.farm_plots
  where player_id = auth.uid()
    and plot_index = p_plot_index;

  if v_crop_id is null then
    raise exception 'No crop to harvest on plot % for this player', p_plot_index;
  end if;

  if v_ready_at > now() then
    raise exception 'Crop on plot % is not ready yet (ready at %)', p_plot_index, v_ready_at;
  end if;

  -- Fetch crop yield_crystals
  select yield_crystals into v_yield_crystals
  from public.crops
  where id = v_crop_id;

  if not found then
    raise exception 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  end if;

  -- Award crystals to player
  update public.profiles
  set crystals = crystals + v_yield_crystals
  where id = auth.uid();

  -- Clear the plot
  update public.farm_plots
  set crop_id = null,
      planted_at = null,
      ready_at = null
  where player_id = auth.uid()
    and plot_index = p_plot_index;

  -- Fetch and return updated crystals
  select crystals into v_new_crystals
  from public.profiles
  where id = auth.uid();

  return v_new_crystals;
end;
$$;

comment on function public.harvest_plot(integer) is 'Harvest a ready crop from farm plot, award yield_crystals to player, clear plot. Returns new player crystal balance.';
-- Create the recipes table for the factory system
create table public.recipes (
  id serial primary key,
  name text unique not null,
  input jsonb not null,
  output jsonb not null,
  minutes integer not null
);

-- Seed initial recipe
insert into public.recipes (name, input, output, minutes) values
('Bread', '{"Wheat": 3}', '{"crystals": 15}', 3);
-- Create the factories table for the factory system
create table public.factories (
  player_id uuid not null references public.profiles(id) on delete cascade,
  factory_type text not null,
  level integer not null default 1,
  primary key (player_id, factory_type)
);

-- Enable RLS
ALTER TABLE public.factories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own factories" ON public.factories
  FOR SELECT
  TO authenticated
  USING (player_id = auth.uid());

CREATE POLICY "Users insert own factories" ON public.factories
  FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

CREATE POLICY "Users update own factories" ON public.factories
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

CREATE POLICY "Users delete own factories" ON public.factories
  FOR DELETE
  TO authenticated
  USING (player_id = auth.uid());

-- Seed 1 "Rune Bakery" factory after profile creation

create or replace function public.seed_factories_for_profile()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.factories (player_id, factory_type, level)
  values (new.id, 'Rune Bakery', 1);
  return new;
end;
$$;

-- trigger the function on insert
create trigger on_profile_created_factories
  after insert on public.profiles
  for each row
  execute function public.seed_factories_for_profile();
-- Create the factory_queue table for managing factory production queues
create table public.factory_queue (
  player_id uuid not null references public.profiles(id) on delete cascade,
  factory_type text not null,
  recipe_id integer not null references public.recipes(id),
  slot integer not null check (slot >= 1),
  started_at timestamptz default now(),
  finishes_at timestamptz not null,
  foreign key (player_id, factory_type) references public.factories(player_id, factory_type),
  primary key (player_id, factory_type, slot)
);

-- Enable RLS
alter table public.factory_queue enable row level security;

-- RLS policies
create policy "Users view own factory_queue" on public.factory_queue
  for select to authenticated
  using (player_id = auth.uid());

create policy "Users insert own factory_queue" on public.factory_queue
  for insert to authenticated
  with check (player_id = auth.uid());

create policy "Users update own factory_queue" on public.factory_queue
  for update to authenticated
  using (player_id = auth.uid())
  with check (player_id = auth.uid());

create policy "Users delete own factory_queue" on public.factory_queue
  for delete to authenticated
  using (player_id = auth.uid());

-- Index for efficient querying of finished productions
create index factory_queue_finishes_at_idx on public.factory_queue (finishes_at);
-- Enable realtime updates for factory_queue table
ALTER PUBLICATION supabase_realtime ADD TABLE public.factory_queue;
-- Add resources jsonb column to profiles for storing inventory resources like wheat, crystals etc.
alter table public.profiles 
add column resources jsonb default '{}'::jsonb;
-- Create RPC function to start factory production: check inventory, deduct resources, add to queue slot
create or replace function public.start_factory_production(
  p_factory_type text,
  p_recipe_name text
)
returns void
language plpgsql
security definer
as $$
declare
  v_player_id uuid := auth.uid();
  v_recipe record;
  v_slot_count integer;
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
begin
  -- Validate factory exists
  if not exists (
    select 1 from public.factories 
    where player_id = v_player_id 
    and factory_type = p_factory_type
  ) then
    raise exception 'Factory "%" does not exist for this player', p_factory_type;
  end if;

  -- Get recipe details
  select * into v_recipe 
  from public.recipes 
  where name = p_recipe_name;

  if not found then
    raise exception 'Recipe "%" does not exist', p_recipe_name;
  end if;

  -- Check available slots (max 2)
  select count(*) into v_slot_count
  from public.factory_queue
  where player_id = v_player_id
  and factory_type = p_factory_type;

  if v_slot_count >= 2 then
    raise exception 'Factory "%" queue is full (max 2 slots)', p_factory_type;
  end if;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources
  for v_input_key, v_input_qty_str in
    select key, value from jsonb_each_text(v_recipe.input)
  loop
    v_input_qty := v_input_qty_str::integer;
    v_current_qty := coalesce(
      (select (resources ->> v_input_key)::integer from public.profiles where id = v_player_id),
      0
    );

    if v_current_qty < v_input_qty then
      raise exception 'Insufficient "%": required %, available %', v_input_key, v_input_qty, v_current_qty;
    end if;

    -- Deduct resource
    update public.profiles set
      resources = jsonb_set(
        resources,
        array[v_input_key],
        (v_current_qty - v_input_qty)::jsonb,
        true
      )
    where id = v_player_id;
  end loop;

  -- Insert into queue
  insert into public.factory_queue (
    player_id,
    factory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  ) values (
    v_player_id,
    p_factory_type,
    v_recipe.id,
    v_next_slot,
    now(),
    now() + (v_recipe.minutes * interval '1 minute')
  );
end;
$$;

comment on function public.start_factory_production(text, text) is 'Start production in a factory: deducts input resources from player inventory, adds entry to factory queue (max 2 slots).';
-- Create RPC function to collect completed factory production from Rune Bakery slot: check ready, add crystals from recipe output, remove queue entry
create or replace function public.collect_factory(p_slot integer)
returns bigint
language plpgsql
security definer
as $$
declare
  v_player_id uuid := auth.uid();
  v_factory_type text := 'Rune Bakery';
  v_queue record;
  v_output jsonb;
  v_yield_crystals integer;
  v_new_crystals bigint;
begin
  -- Fetch queue entry
  select * into v_queue
  from public.factory_queue
  where player_id = v_player_id
    and factory_type = v_factory_type
    and slot = p_slot;

  if not found then
    raise exception 'No production found in slot % of %', p_slot, v_factory_type;
  end if;

  if v_queue.finishes_at > now() then
    raise exception 'Production in slot % of % not ready yet (finishes at %)', p_slot, v_factory_type, v_queue.finishes_at;
  end if;

  -- Get recipe output
  select output into v_output
  from public.recipes
  where id = v_queue.recipe_id;

  if not found then
    raise exception 'Recipe with id % not found', v_queue.recipe_id;
  end if;

  -- Extract crystals yield
  v_yield_crystals := (v_output ->> 'crystals')::integer;
  if v_yield_crystals is null then
    raise exception 'Recipe output must contain "crystals" field';
  end if;

  -- Award crystals to player
  update public.profiles
  set crystals = crystals + v_yield_crystals
  where id = v_player_id;

  -- Remove queue entry
  delete from public.factory_queue
  where player_id = v_player_id
    and factory_type = v_factory_type
    and slot = p_slot;

  -- Return updated crystals balance
  select crystals into v_new_crystals
  from public.profiles
  where id = v_player_id;

  return v_new_crystals;
end;
$$;

comment on function public.collect_factory(integer) is 'Collect completed Rune Bakery production from slot: awards recipe output crystals, clears queue slot. Returns new player crystals balance.';
-- Create inventory table to track player items (wheat, bread, etc.)
CREATE TABLE IF NOT EXISTS public.inventory (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id integer NOT NULL,
  quantity bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (player_id, item_id)
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Create policies for owner-only access
CREATE POLICY "Users can view own inventory" ON public.inventory
  FOR SELECT TO authenticated
  USING ( auth.uid() = player_id );

CREATE POLICY "Users can insert own inventory" ON public.inventory
  FOR INSERT TO authenticated
  WITH CHECK ( auth.uid() = player_id );

CREATE POLICY "Users can update own inventory" ON public.inventory
  FOR UPDATE TO authenticated
  USING ( auth.uid() = player_id )
  WITH CHECK ( auth.uid() = player_id );

CREATE POLICY "Users can delete own inventory" ON public.inventory
  FOR DELETE TO authenticated
  USING ( auth.uid() = player_id );

-- Enable realtime subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory;
-- Seed starting inventory (wheat x10) after profile creation

create or replace function public.seed_starting_inventory_for_profile()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.inventory (player_id, item_id, quantity) values (new.id, 1, 10)
  on conflict (player_id, item_id) do nothing;
  return new;
end;
$$;

create trigger on_profile_inventory_seeded
  after insert on public.profiles
  for each row
  execute function public.seed_starting_inventory_for_profile();
-- Phase 6.5: Integrate farm/factory RPCs with inventory table (item_id 1=wheat, 2=bread, 3=crystals)

-- Update bread recipe to produce bread and crystals
UPDATE public.recipes
SET output = '{"bread": 1, "crystals": 10}'::jsonb
WHERE name = 'Bread';

-- 1. Updated harvest_plot RPC: harvest adds wheat (item_id=1) to inventory instead of profiles.crystals
CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_wheat integer;
  v_new_wheat bigint;
BEGIN
  -- Fetch current plot crop info
  SELECT crop_id, ready_at INTO v_crop_id, v_ready_at
  FROM public.farm_plots
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  IF v_crop_id IS NULL THEN
    RAISE EXCEPTION 'No crop to harvest on plot % for this player', p_plot_index;
  END IF;

  IF v_ready_at > now() THEN
    RAISE EXCEPTION 'Crop on plot % is not ready yet (ready at %)', p_plot_index, v_ready_at;
  END IF;

  -- Fetch crop yield (repurposed yield_crystals as wheat yield)
  SELECT yield_crystals INTO v_yield_wheat
  FROM public.crops
  WHERE id = v_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  END IF;

  -- Award wheat to player inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (auth.uid(), 1, v_yield_wheat::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Clear the plot
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  -- Fetch and return updated wheat quantity
  SELECT COALESCE(quantity, 0) INTO v_new_wheat
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = 1;

  RETURN v_new_wheat;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds wheat (item_id=1) yield to inventory, clears plot. Returns new wheat balance.';

-- 2. Updated start_factory_production RPC: deduct input (wheat item_id=1) from inventory instead of profiles.resources
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

  -- Check available slots (max 2)
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  IF v_slot_count >= 2 THEN
    RAISE EXCEPTION 'Factory "%" queue is full (max 2 slots)', p_factory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources from inventory
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id
    CASE v_input_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'bread' THEN v_item_id := 2;
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

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources (wheat/bread item_ids 1/2) from inventory, adds to queue (max 2 slots).';

-- 3. Updated collect_factory RPC: add recipe output (bread/crystals item_ids 2/3) to inventory instead of profiles.crystals
CREATE OR REPLACE FUNCTION public.collect_factory(p_slot integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory_type text := 'Rune Bakery';
  v_queue record;
  v_output jsonb;
  v_key text;
  v_qty_str text;
  v_qty integer;
  v_item_id integer;
  v_new_crystals bigint;
BEGIN
  -- Fetch queue entry
  SELECT * INTO v_queue
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = v_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No production found in slot % of %', p_slot, v_factory_type;
  END IF;

  IF v_queue.finishes_at > now() THEN
    RAISE EXCEPTION 'Production in slot % of % not ready yet (finishes at %)', p_slot, v_factory_type, v_queue.finishes_at;
  END IF;

  -- Get recipe output
  SELECT output INTO v_output
  FROM public.recipes
  WHERE id = v_queue.recipe_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe with id % not found', v_queue.recipe_id;
  END IF;

  -- Award output resources to inventory
  FOR v_key, v_qty_str IN SELECT key, value FROM jsonb_each_text(v_output) LOOP
    v_qty := v_qty_str::integer;

    -- Map output resource name to item_id
    CASE v_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'bread' THEN v_item_id := 2;
      WHEN 'crystals' THEN v_item_id := 3;
      ELSE RAISE EXCEPTION 'Unsupported output resource "%"', v_key;
    END CASE;

    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_item_id, v_qty::bigint)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + excluded.quantity;
  END LOOP;

  -- Remove queue entry
  DELETE FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = v_factory_type
    AND slot = p_slot;

  -- Return updated crystals quantity (for frontend compatibility)
  SELECT COALESCE(quantity, 0) INTO v_new_crystals
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = 3;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'produce', 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.collect_factory(integer) IS 'Collect completed Rune Bakery production: adds recipe output (bread/crystals item_ids 2/3) to inventory, clears slot. Returns new crystals quantity.';
-- Add last_claimed_date column to profiles table for daily reward tracking
alter table public.profiles
add column last_claimed_date date;

comment on column public.profiles.last_claimed_date is 'Date when player last claimed their daily reward';

-- Create RPC function for claiming daily rewards
CREATE OR REPLACE FUNCTION public.claim_daily_reward()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_today date;
  v_last_claimed date;
  v_current_crystals integer;
  v_reward_crystals integer := 500;
  v_new_crystals integer;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'No authenticated user'
    );
  END IF;

  v_today := CURRENT_DATE;

  -- Get current profile data
  SELECT last_claimed_date, crystals
  INTO v_last_claimed, v_current_crystals
  FROM public.profiles
  WHERE id = v_user_id;

  -- Check if already claimed today
  IF v_last_claimed = v_today THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Daily reward already claimed today',
      'alreadyClaimed', true
    );
  END IF;

  -- Calculate new crystal total
  v_new_crystals := v_current_crystals + v_reward_crystals;

  -- Update profile
  UPDATE public.profiles
  SET
    crystals = v_new_crystals,
    last_claimed_date = v_today
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Successfully claimed %s crystals!', v_reward_crystals),
    'crystalsAwarded', v_reward_crystals,
    'alreadyClaimed', false
  );
END;
$$;

COMMENT ON FUNCTION public.claim_daily_reward() IS 'Claim daily reward of 500 crystals for authenticated user. Can only be claimed once per day.';
-- Enable RLS on recipes table (shared reference data)
ALTER TABLE public.recipes
  ENABLE ROW LEVEL SECURITY;

-- Policy: All authenticated users can read recipes
DROP POLICY IF EXISTS "Enable read access for authenticated users on recipes" ON public.recipes;
CREATE POLICY "Enable read access for authenticated users on recipes"
  ON public.recipes
  FOR SELECT
  TO authenticated
  USING (true);
-- Create coven table
CREATE TABLE public.coven (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  emblem text,
  leader_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  -- Enhanced columns
  description TEXT,
  visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'invite_only')),
  member_count INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- Create coven_members table
CREATE TABLE public.coven_members (
  coven_id uuid NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text DEFAULT 'member' CHECK (role IN ('member', 'elder', 'leader')),
  contribution bigint DEFAULT 0,
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (coven_id, player_id),
  -- Enhanced columns
  invited_by UUID REFERENCES public.profiles(id),
  invite_accepted_at TIMESTAMPTZ,
  last_active TIMESTAMPTZ,
  title TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_invitations table
CREATE TABLE public.coven_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coven_id UUID NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES public.profiles(id),
  invitee_id UUID NOT NULL REFERENCES public.profiles(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  message TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_resources table
CREATE TABLE public.coven_resources (
  coven_id UUID PRIMARY KEY REFERENCES public.coven(id) ON DELETE CASCADE,
  crystals BIGINT DEFAULT 0,
  herbs BIGINT DEFAULT 0,
  runes BIGINT DEFAULT 0,
  artifacts BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_activity_log table
CREATE TABLE public.coven_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coven_id UUID NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES public.profiles(id),
  action TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for coven table
CREATE INDEX idx_coven_leader_id ON public.coven(leader_id);
CREATE INDEX idx_coven_visibility ON public.coven(visibility);
CREATE INDEX idx_coven_member_count ON public.coven(member_count);
CREATE INDEX idx_coven_updated_at ON public.coven(updated_at);

-- Create indexes for coven_members table
CREATE INDEX idx_coven_members_player_id ON public.coven_members(player_id);
CREATE INDEX idx_coven_members_coven_id ON public.coven_members(coven_id);
CREATE INDEX idx_coven_members_role ON public.coven_members(role);
CREATE INDEX idx_coven_members_last_active ON public.coven_members(last_active);
CREATE INDEX idx_coven_members_contribution ON public.coven_members(contribution);

-- Create indexes for coven_invitations table
CREATE INDEX idx_coven_invitations_coven_id ON public.coven_invitations(coven_id);
CREATE INDEX idx_coven_invitations_invitee_id ON public.coven_invitations(invitee_id);
CREATE INDEX idx_coven_invitations_status ON public.coven_invitations(status);

-- Create indexes for coven_activity_log table
CREATE INDEX idx_coven_activity_log_coven_id ON public.coven_activity_log(coven_id);
CREATE INDEX idx_coven_activity_log_actor_id ON public.coven_activity_log(actor_id);
CREATE INDEX idx_coven_activity_log_action ON public.coven_activity_log(action);
CREATE INDEX idx_coven_activity_log_created_at ON public.coven_activity_log(created_at);

-- Enable RLS on coven table
ALTER TABLE public.coven ENABLE ROW LEVEL SECURITY;

-- Policy: Read access based on visibility settings
DROP POLICY IF EXISTS "Enable conditional read access on coven" ON public.coven;
CREATE POLICY "Enable conditional read access on coven"
  ON public.coven
  FOR SELECT
  TO authenticated
  USING (
    visibility = 'public' OR
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven.id AND cm.player_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM public.coven_invitations ci
      WHERE ci.coven_id = coven.id AND ci.invitee_id = auth.uid() AND ci.status = 'pending'
    )
  );

-- Policy: Leaders can update their own coven
DROP POLICY IF EXISTS "Leaders can update own coven" ON public.coven;
CREATE POLICY "Leaders can update own coven"
  ON public.coven
  FOR UPDATE
  TO authenticated
  USING (leader_id = auth.uid())
  WITH CHECK (leader_id = auth.uid());

-- Policy: Authenticated users can create covens (they become leader)
DROP POLICY IF EXISTS "Users can create coven" ON public.coven;
CREATE POLICY "Users can create coven"
  ON public.coven
  FOR INSERT
  TO authenticated
  WITH CHECK (leader_id = auth.uid());

-- Enable RLS on coven_members table
ALTER TABLE public.coven_members ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view members of their coven
DROP POLICY IF EXISTS "Members can view coven members" ON public.coven_members;
CREATE POLICY "Members can view coven members"
  ON public.coven_members
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_members.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Policy: Users can join covens (insert themselves)
DROP POLICY IF EXISTS "Users can join coven" ON public.coven_members;
CREATE POLICY "Users can join coven"
  ON public.coven_members
  FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can leave their own coven
DROP POLICY IF EXISTS "Users can leave coven" ON public.coven_members;
CREATE POLICY "Users can leave coven"
  ON public.coven_members
  FOR DELETE
  TO authenticated
  USING (player_id = auth.uid());

-- Policy: Leaders can update/delete members (kick, promote, etc.)
DROP POLICY IF EXISTS "Leaders can manage coven members" ON public.coven_members;
CREATE POLICY "Leaders can manage coven members"
  ON public.coven_members
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  );

-- Policy: Leaders can delete members (kick)
DROP POLICY IF EXISTS "Leaders can kick coven members" ON public.coven_members;
CREATE POLICY "Leaders can kick coven members"
  ON public.coven_members
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  );

-- Policy: Members can update their own last_active timestamp
DROP POLICY IF EXISTS "Members can update their last_active" ON public.coven_members;
CREATE POLICY "Members can update their last_active"
  ON public.coven_members
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

-- Enable RLS on coven_invitations table
ALTER TABLE public.coven_invitations ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own invitations
DROP POLICY IF EXISTS "Users can view their invitations" ON public.coven_invitations;
CREATE POLICY "Users can view their invitations"
  ON public.coven_invitations
  FOR SELECT
  TO authenticated
  USING (invitee_id = auth.uid());

-- Policy: Leaders/elders can view invitations for their coven
DROP POLICY IF EXISTS "Leaders can view coven invitations" ON public.coven_invitations;
CREATE POLICY "Leaders can view coven invitations"
  ON public.coven_invitations
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_invitations.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Policy: Leaders/elders can create invitations for their coven
DROP POLICY IF EXISTS "Leaders can create coven invitations" ON public.coven_invitations;
CREATE POLICY "Leaders can create coven invitations"
  ON public.coven_invitations
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_invitations.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Policy: Users can update their own invitations (accept/decline)
DROP POLICY IF EXISTS "Users can update their invitations" ON public.coven_invitations;
CREATE POLICY "Users can update their invitations"
  ON public.coven_invitations
  FOR UPDATE
  TO authenticated
  USING (invitee_id = auth.uid())
  WITH CHECK (invitee_id = auth.uid());

-- Enable RLS on coven_resources table
ALTER TABLE public.coven_resources ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view coven resources
DROP POLICY IF EXISTS "Members can view coven resources" ON public.coven_resources;
CREATE POLICY "Members can view coven resources"
  ON public.coven_resources
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Policy: Leaders/elders can update coven resources
DROP POLICY IF EXISTS "Leaders can update coven resources" ON public.coven_resources;
CREATE POLICY "Leaders can update coven resources"
  ON public.coven_resources
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Enable RLS on coven_activity_log table
ALTER TABLE public.coven_activity_log ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view coven activity
DROP POLICY IF EXISTS "Members can view coven activity" ON public.coven_activity_log;
CREATE POLICY "Members can view coven activity"
  ON public.coven_activity_log
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_activity_log.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Create RPC function to transfer coven leadership
CREATE OR REPLACE FUNCTION public.transfer_coven_leadership(p_coven_id UUID, p_new_leader_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Check if current user is leader
  IF NOT EXISTS (
    SELECT 1 FROM public.coven 
    WHERE id = p_coven_id AND leader_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the current leader can transfer leadership';
  END IF;

  -- Check if new leader is a member
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id AND player_id = p_new_leader_id
  ) THEN
    RAISE EXCEPTION 'New leader must be a member of the coven';
  END IF;

  -- Update coven leader
  UPDATE public.coven 
  SET leader_id = p_new_leader_id 
  WHERE id = p_coven_id;

  -- Update roles
  UPDATE public.coven_members 
  SET role = 'leader' 
  WHERE coven_id = p_coven_id AND player_id = p_new_leader_id;

  UPDATE public.coven_members 
  SET role = 'elder' 
  WHERE coven_id = p_coven_id AND player_id = auth.uid();

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, target_type, target_id)
  VALUES (p_coven_id, auth.uid(), 'leadership_transfer', 'player', p_new_leader_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.transfer_coven_leadership(UUID, UUID) IS 'Transfer coven leadership to another member';

-- Create RPC function to disband coven
CREATE OR REPLACE FUNCTION public.disband_coven(p_coven_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Check if current user is leader
  IF NOT EXISTS (
    SELECT 1 FROM public.coven 
    WHERE id = p_coven_id AND leader_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the leader can disband the coven';
  END IF;

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, metadata)
  VALUES (p_coven_id, auth.uid(), 'coven_disbanded', jsonb_build_object('member_count', (
    SELECT COUNT(*) FROM public.coven_members WHERE coven_id = p_coven_id
  )));

  -- Delete coven (cascade will handle members)
  DELETE FROM public.coven WHERE id = p_coven_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.disband_coven(UUID) IS 'Disband a coven permanently';

-- Create RPC function to invite player to coven
CREATE OR REPLACE FUNCTION public.invite_to_coven(p_coven_id UUID, p_invitee_id UUID, p_message TEXT DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
  v_invitation_id UUID;
BEGIN
  -- Check if current user is member with invite permissions
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id 
    AND player_id = auth.uid() 
    AND role IN ('leader', 'elder')
  ) THEN
    RAISE EXCEPTION 'Only leaders and elders can invite players';
  END IF;

  -- Check if invitee is already a member
  IF EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id AND player_id = p_invitee_id
  ) THEN
    RAISE EXCEPTION 'Player is already a member of this coven';
  END IF;

  -- Create invitation
  INSERT INTO public.coven_invitations (
    coven_id, inviter_id, invitee_id, message, expires_at
  ) VALUES (
    p_coven_id, auth.uid(), p_invitee_id, p_message, NOW() + INTERVAL '7 days'
  ) RETURNING id INTO v_invitation_id;

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, target_type, target_id)
  VALUES (p_coven_id, auth.uid(), 'invitation_sent', 'player', p_invitee_id);

  RETURN v_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.invite_to_coven(UUID, UUID, TEXT) IS 'Invite a player to join a coven';

-- Create function to update coven member count
CREATE OR REPLACE FUNCTION public.update_coven_member_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.coven 
    SET member_count = member_count + 1, updated_at = NOW()
    WHERE id = NEW.coven_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.coven 
    SET member_count = member_count - 1, updated_at = NOW()
    WHERE id = OLD.coven_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update coven member count
DROP TRIGGER IF EXISTS update_coven_member_count_trigger ON public.coven_members;
CREATE TRIGGER update_coven_member_count_trigger
AFTER INSERT OR DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.update_coven_member_count();

-- Create function to auto-delete empty covens
CREATE OR REPLACE FUNCTION public.auto_delete_empty_coven()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- If this was the last member, delete the coven
    IF NOT EXISTS (
      SELECT 1 FROM public.coven_members 
      WHERE coven_id = OLD.coven_id
    ) THEN
      DELETE FROM public.coven WHERE id = OLD.coven_id;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-delete empty covens
DROP TRIGGER IF EXISTS auto_delete_empty_coven_trigger ON public.coven_members;
CREATE TRIGGER auto_delete_empty_coven_trigger
AFTER DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.auto_delete_empty_coven();

-- Create function to update member last active
CREATE OR REPLACE FUNCTION public.update_member_last_active()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coven_members 
  SET last_active = NOW(), updated_at = NOW()
  WHERE coven_id = NEW.coven_id AND player_id = auth.uid();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.update_member_last_active() IS 'Update last active timestamp for a coven member';
-- Expand crops table with more crop types and add item_id mapping

-- Add item_id column to crops table to map to inventory items
ALTER TABLE public.crops ADD COLUMN IF NOT EXISTS item_id integer;

-- Update existing crops with item_id
UPDATE public.crops SET item_id = 1 WHERE name = 'Wheat';
UPDATE public.crops SET item_id = 2 WHERE name = 'Carrot';

-- Add new crops with varied growth times and yields
INSERT INTO public.crops (name, grow_minutes, yield_crystals, item_id) VALUES
('Potato', 3, 15, 3),
('Tomato', 4, 20, 4),
('Corn', 5, 25, 5),
('Pumpkin', 8, 40, 6),
('Berry', 2, 12, 11),
('Herbs', 3, 18, 12),
('Magic Mushroom', 10, 50, 13),
('Enchanted Flower', 12, 60, 14)
ON CONFLICT (name) DO NOTHING;

-- Make item_id NOT NULL after populating
ALTER TABLE public.crops ALTER COLUMN item_id SET NOT NULL;

-- Add comment
COMMENT ON COLUMN public.crops.item_id IS 'Maps to inventory item_id for harvested crops';


-- Update harvest_plot RPC to handle all crop types and yield appropriate items based on crop.item_id

CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_qty integer;
  v_item_id integer;
  v_new_item_qty bigint;
BEGIN
  -- Fetch current plot crop info
  SELECT crop_id, ready_at INTO v_crop_id, v_ready_at
  FROM public.farm_plots
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  IF v_crop_id IS NULL THEN
    RAISE EXCEPTION 'No crop to harvest on plot % for this player', p_plot_index;
  END IF;

  IF v_ready_at > now() THEN
    RAISE EXCEPTION 'Crop on plot % is not ready yet (ready at %)', p_plot_index, v_ready_at;
  END IF;

  -- Fetch crop yield and item_id
  SELECT yield_crystals, item_id INTO v_yield_qty, v_item_id
  FROM public.crops
  WHERE id = v_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  END IF;

  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'Crop % does not have an item_id mapping', v_crop_id;
  END IF;

  -- Award crop item to player inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (auth.uid(), v_item_id, v_yield_qty::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Clear the plot
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  -- Fetch and return updated item quantity
  SELECT COALESCE(quantity, 0) INTO v_new_item_qty
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = v_item_id;

  -- Check achievements
  PERFORM public.check_achievements('harvest_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'harvest', 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('harvest', 1);

  RETURN v_new_item_qty;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds crop item (based on crop.item_id) yield to inventory, clears plot. Returns new item quantity.';


-- Expand recipes table with new recipes using different plant combinations
-- Note: Recipe inputs/outputs use lowercase names that map to item_ids in RPCs

-- Update existing Bread recipe to use lowercase 'wheat' for consistency
UPDATE public.recipes
SET input = '{"wheat": 3}'::jsonb
WHERE name = 'Bread';

-- Add new recipes with varied plant combinations
INSERT INTO public.recipes (name, input, output, minutes) VALUES
('Vegetable Stew', '{"potato": 2, "tomato": 2, "carrot": 1}'::jsonb, '{"crystals": 50}'::jsonb, 5),
('Corn Bread', '{"corn": 2, "wheat": 2}'::jsonb, '{"crystals": 30}'::jsonb, 4),
('Pumpkin Pie', '{"pumpkin": 1, "wheat": 3}'::jsonb, '{"crystals": 60}'::jsonb, 6),
('Herbal Tea', '{"herbs": 2, "berry": 3}'::jsonb, '{"crystals": 25}'::jsonb, 3),
('Magic Potion', '{"magic_mushroom": 1, "enchanted_flower": 1}'::jsonb, '{"crystals": 100}'::jsonb, 10),
('Fruit Salad', '{"berry": 2, "tomato": 2}'::jsonb, '{"crystals": 35}'::jsonb, 4)
ON CONFLICT (name) DO NOTHING;

COMMENT ON TABLE public.recipes IS 'Factory recipes: input/output use lowercase item names that map to item_ids in RPC functions';


-- Update start_factory_production RPC to handle all new crop/item types

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

  -- Check available slots (max 2)
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  IF v_slot_count >= 2 THEN
    RAISE EXCEPTION 'Factory "%" queue is full (max 2 slots)', p_factory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

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

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources (all crop/item types) from inventory, adds to queue (max 2 slots).';


-- Create seed shop system for purchasing seeds with crystals

-- Create seed_shop table with crop prices
CREATE TABLE IF NOT EXISTS public.seed_shop (
  crop_id integer PRIMARY KEY REFERENCES public.crops(id) ON DELETE CASCADE,
  price_crystals integer NOT NULL DEFAULT 10,
  available boolean NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.seed_shop ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view seed shop
CREATE POLICY "Anyone can view seed shop" ON public.seed_shop
  FOR SELECT TO authenticated
  USING (true);

-- Seed shop with prices for all crops (cheaper than selling harvested crops)
INSERT INTO public.seed_shop (crop_id, price_crystals, available) VALUES
(1, 5, true),   -- Wheat: 5 crystals
(2, 10, true),  -- Carrot: 10 crystals
(3, 8, true),   -- Potato: 8 crystals
(4, 10, true),   -- Tomato: 10 crystals
(5, 12, true),   -- Corn: 12 crystals
(6, 20, true),   -- Pumpkin: 20 crystals
(7, 6, true),   -- Berry: 6 crystals
(8, 9, true),   -- Herbs: 9 crystals
(9, 25, true),  -- Magic Mushroom: 25 crystals
(10, 30, true)   -- Enchanted Flower: 30 crystals
ON CONFLICT (crop_id) DO UPDATE SET
  price_crystals = EXCLUDED.price_crystals,
  available = EXCLUDED.available;

-- Create RPC function to buy seeds
CREATE OR REPLACE FUNCTION public.buy_seed(p_crop_id integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_seed_price integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
BEGIN
  -- Get seed price
  SELECT price_crystals INTO v_seed_price
  FROM public.seed_shop
  WHERE crop_id = p_crop_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Seed for crop_id % is not available in the shop', p_crop_id;
  END IF;

  -- Get current crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_seed_price THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_seed_price, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_seed_price
  WHERE id = v_player_id;

  -- Add seed to inventory (seeds use item_id 10 for "Enchanted Seeds" or we can create a seed inventory)
  -- For now, we'll add the crop's item_id directly (player can plant it immediately)
  -- Actually, seeds should be separate. Let's use a seed inventory approach.
  -- For simplicity, we'll just deduct crystals and the player can plant directly.
  -- The seed purchase is just a crystal cost to unlock planting that crop.

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.buy_seed(integer) IS 'Purchase seed for a crop using crystals. Returns new crystal balance.';

-- Note: In this implementation, buying a seed just deducts crystals.
-- The player can then plant that crop type. For a more complex system,
-- you could add a seeds inventory table, but for simplicity we'll allow
-- direct planting after "purchasing" (which is really just paying to unlock/plant).


-- Create marketplace system for selling items for crystals

-- Create marketplace table with sell prices
CREATE TABLE IF NOT EXISTS public.marketplace (
  item_id integer PRIMARY KEY,
  sell_price_crystals integer NOT NULL DEFAULT 1,
  available boolean NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.marketplace ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view marketplace prices
CREATE POLICY "Anyone can view marketplace" ON public.marketplace
  FOR SELECT TO authenticated
  USING (true);

-- Seed marketplace with sell prices for all items
-- Prices are typically lower than seed costs to create economy
INSERT INTO public.marketplace (item_id, sell_price_crystals, available) VALUES
(1, 3, true),   -- Wheat: 3 crystals per unit
(2, 8, true),  -- Carrot: 8 crystals per unit
(3, 5, true),   -- Potato: 5 crystals per unit
(4, 7, true),   -- Tomato: 7 crystals per unit
(5, 10, true),  -- Corn: 10 crystals per unit
(6, 18, true),  -- Pumpkin: 18 crystals per unit
(8, 12, true),  -- Bread: 12 crystals per unit
(11, 4, true),  -- Berry: 4 crystals per unit
(12, 6, true),  -- Herbs: 6 crystals per unit
(13, 20, true), -- Magic Mushroom: 20 crystals per unit
(14, 25, true)  -- Enchanted Flower: 25 crystals per unit
ON CONFLICT (item_id) DO UPDATE SET
  sell_price_crystals = EXCLUDED.sell_price_crystals,
  available = EXCLUDED.available;

-- Create RPC function to sell items
CREATE OR REPLACE FUNCTION public.sell_item(p_item_id integer, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_sell_price integer;
  v_current_qty bigint;
  v_total_crystals bigint;
  v_new_crystals bigint;
BEGIN
  -- Validate quantity
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than 0';
  END IF;

  -- Get sell price
  SELECT sell_price_crystals INTO v_sell_price
  FROM public.marketplace
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % is not available for sale in the marketplace', p_item_id;
  END IF;

  -- Get current inventory quantity
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient quantity: required %, available %', p_quantity, v_current_qty;
  END IF;

  -- Calculate total crystals to award
  v_total_crystals := v_sell_price * p_quantity;

  -- Deduct items from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Award crystals to player
  UPDATE public.profiles
  SET crystals = crystals + v_total_crystals
  WHERE id = v_player_id;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'sell', p_quantity);

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'crystals_awarded', v_total_crystals,
    'new_crystal_balance', v_new_crystals,
    'items_sold', p_quantity
  );
END;
$$;

COMMENT ON FUNCTION public.sell_item(integer, integer) IS 'Sell items from inventory for crystals. Returns success status, crystals awarded, and new balance.';


-- Create skyport orders system for transportation orders

-- Create skyport_orders table
CREATE TABLE IF NOT EXISTS public.skyport_orders (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  order_type text NOT NULL CHECK (order_type IN ('quick', 'standard', 'premium')),
  requirements jsonb NOT NULL, -- {item_id: quantity} format
  rewards jsonb NOT NULL, -- {crystals: amount, xp: amount, items: {item_id: quantity}}
  expires_at timestamptz NOT NULL,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.skyport_orders ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own orders
CREATE POLICY "Players can view own orders" ON public.skyport_orders
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own orders" ON public.skyport_orders
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own orders" ON public.skyport_orders
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.skyport_orders;

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_skyport_orders_player_active ON public.skyport_orders(player_id, completed_at) WHERE completed_at IS NULL;

-- Function to generate new orders for a player
CREATE OR REPLACE FUNCTION public.generate_skyport_orders(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_count integer;
  v_order_type text;
  v_requirements jsonb;
  v_rewards jsonb;
  v_expires_minutes integer;
  v_i integer;
BEGIN
  -- Count active orders
  SELECT count(*) INTO v_order_count
  FROM public.skyport_orders
  WHERE player_id = p_player_id AND completed_at IS NULL;

  -- Generate orders up to max (3 quick, 2 standard, 1 premium = 6 total)
  -- Quick orders (helicopter) - 3 slots, 30 min expiry
  FOR v_i IN 1..3 LOOP
    IF v_order_count < 6 THEN
      v_order_type := 'quick';
      v_expires_minutes := 30;
      
      -- Generate random requirements (1-2 items, small quantities)
      v_requirements := jsonb_build_object(
        floor(random() * 10 + 1)::text, floor(random() * 3 + 1)::text
      );
      
      -- Generate rewards (small crystals, XP)
      v_rewards := jsonb_build_object(
        'crystals', floor(random() * 20 + 10),
        'xp', floor(random() * 50 + 25)
      );
      
      INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
      VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
      
      v_order_count := v_order_count + 1;
    END IF;
  END LOOP;
  
  -- Standard orders (skyport) - 2 slots, 2 hour expiry
  FOR v_i IN 1..2 LOOP
    IF v_order_count < 6 THEN
      v_order_type := 'standard';
      v_expires_minutes := 120;
      
      -- Generate random requirements (2-3 items, medium quantities)
      v_requirements := jsonb_build_object(
        floor(random() * 10 + 1)::text, floor(random() * 5 + 2)::text,
        floor(random() * 10 + 1)::text, floor(random() * 5 + 2)::text
      );
      
      -- Generate rewards (medium crystals, XP)
      v_rewards := jsonb_build_object(
        'crystals', floor(random() * 50 + 30),
        'xp', floor(random() * 100 + 50)
      );
      
      INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
      VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
      
      v_order_count := v_order_count + 1;
    END IF;
  END LOOP;
  
  -- Premium orders (spirit whale) - 1 slot, 4 hour expiry
  IF v_order_count < 6 THEN
    v_order_type := 'premium';
    v_expires_minutes := 240;
    
    -- Generate random requirements (3-4 items, larger quantities)
    v_requirements := jsonb_build_object(
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text,
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text,
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text
    );
    
    -- Generate rewards (large crystals, XP, bonus items)
    v_rewards := jsonb_build_object(
      'crystals', floor(random() * 100 + 75),
      'xp', floor(random() * 200 + 150),
      'items', jsonb_build_object('3', '10') -- Bonus crystals item
    );
    
    INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
    VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.generate_skyport_orders(uuid) IS 'Generate new skyport orders for a player (max 6 active orders)';

-- Function to fulfill an order
CREATE OR REPLACE FUNCTION public.fulfill_skyport_order(p_order_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_rewards jsonb;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
  v_key text;
  v_value text;
  v_result jsonb;
BEGIN
  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % not found or does not belong to this player', p_order_id;
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order % has already been completed', p_order_id;
  END IF;

  IF v_order.expires_at < now() THEN
    RAISE EXCEPTION 'Order % has expired', p_order_id;
  END IF;

  v_requirements := v_order.requirements;
  v_rewards := v_order.rewards;

  -- Check and deduct required items
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
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

  -- Award rewards
  -- Crystals
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_rewards->>'crystals')::integer,
        xp = xp + COALESCE((v_rewards->>'xp')::integer, 0)
    WHERE id = v_player_id;
  END IF;

  -- XP (if separate from crystals update)
  IF v_rewards ? 'xp' AND NOT (v_rewards ? 'crystals') THEN
    UPDATE public.profiles
    SET xp = xp + (v_rewards->>'xp')::integer
    WHERE id = v_player_id;
  END IF;

  -- Items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_required_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_required_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark order as completed
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'order', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE((v_rewards->>'crystals')::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fulfill_skyport_order(integer) IS 'Fulfill a skyport order: deduct requirements from inventory, award rewards, mark complete';


-- Create buildings table for city building placement system

CREATE TABLE IF NOT EXISTS public.buildings (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  building_type text NOT NULL,
  grid_x integer NOT NULL CHECK (grid_x >= 0 AND grid_x < 20),
  grid_y integer NOT NULL CHECK (grid_y >= 0 AND grid_y < 20),
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 5),
  created_at timestamptz DEFAULT now(),
  UNIQUE(player_id, grid_x, grid_y) -- One building per grid cell
);

-- Enable RLS
ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own buildings
CREATE POLICY "Players can view own buildings" ON public.buildings
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own buildings" ON public.buildings
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own buildings" ON public.buildings
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own buildings" ON public.buildings
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.buildings;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_buildings_player ON public.buildings(player_id);
CREATE INDEX IF NOT EXISTS idx_buildings_position ON public.buildings(grid_x, grid_y);

-- Building types reference table (for validation and metadata)
CREATE TABLE IF NOT EXISTS public.building_types (
  building_type text PRIMARY KEY,
  name text NOT NULL,
  category text NOT NULL CHECK (category IN ('factory', 'community', 'decoration')),
  base_cost_crystals integer NOT NULL DEFAULT 100,
  size_x integer NOT NULL DEFAULT 1,
  size_y integer NOT NULL DEFAULT 1,
  provides_population integer DEFAULT 0,
  max_level integer DEFAULT 5
);

-- Seed building types
INSERT INTO public.building_types (building_type, name, category, base_cost_crystals, size_x, size_y, provides_population, max_level) VALUES
-- Factories
('rune_bakery', 'Rune Bakery', 'factory', 500, 2, 2, 0, 5),
('potion_workshop', 'Potion Workshop', 'factory', 1000, 2, 2, 0, 5),
('enchanting_lab', 'Enchanting Lab', 'factory', 1500, 2, 2, 0, 5),
('kitchen', 'Kitchen', 'factory', 800, 2, 2, 0, 5),
-- Community Buildings
('town_hall', 'Town Hall', 'community', 2000, 3, 3, 50, 1),
('school', 'School', 'community', 1500, 2, 2, 30, 1),
('hospital', 'Hospital', 'community', 1800, 2, 2, 25, 1),
('cinema', 'Cinema', 'community', 1200, 2, 2, 20, 1),
-- Decorations
('fountain', 'Fountain', 'decoration', 200, 1, 1, 0, 1),
('statue', 'Statue', 'decoration', 150, 1, 1, 0, 1),
('tree', 'Tree', 'decoration', 50, 1, 1, 0, 1)
ON CONFLICT (building_type) DO NOTHING;

-- RPC function to place a building
CREATE OR REPLACE FUNCTION public.place_building(
  p_building_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building_info record;
  v_cost integer;
  v_current_crystals bigint;
  v_building_id integer;
  v_size_x integer;
  v_size_y integer;
  v_check_x integer;
  v_check_y integer;
BEGIN
  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = p_building_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building type "%" does not exist', p_building_type;
  END IF;

  v_cost := v_building_info.base_cost_crystals;
  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Check if player has enough crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
  END IF;

  -- Check if grid cells are available (for multi-cell buildings)
  FOR v_check_x IN p_grid_x..(p_grid_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_grid_y..(p_grid_y + v_size_y - 1) LOOP
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%,%) is already occupied', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Place building (only record top-left corner for multi-cell buildings)
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, p_building_type, p_grid_x, p_grid_y, 1)
  RETURNING id INTO v_building_id;

  -- Update population if community building
  IF v_building_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = COALESCE(population, 0) + v_building_info.provides_population
    WHERE id = v_player_id;
  END IF;

  RETURN v_building_id;
END;
$$;

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Returns building ID.';

-- RPC function to move a building
CREATE OR REPLACE FUNCTION public.move_building(
  p_building_id integer,
  p_new_x integer,
  p_new_y integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_info record;
  v_size_x integer;
  v_size_y integer;
  v_check_x integer;
  v_check_y integer;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Check if new location is available
  FOR v_check_x IN p_new_x..(p_new_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_new_y..(p_new_y + v_size_y - 1) LOOP
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
        AND id != p_building_id
      ) THEN
        RAISE EXCEPTION 'Grid cell (%,%) is already occupied', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Move building
  UPDATE public.buildings
  SET grid_x = p_new_x, grid_y = p_new_y
  WHERE id = p_building_id;
END;
$$;

COMMENT ON FUNCTION public.move_building(integer, integer, integer) IS 'Move a building to a new location on the grid.';

-- RPC function to remove a building
CREATE OR REPLACE FUNCTION public.remove_building(p_building_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_info record;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  -- Remove building
  DELETE FROM public.buildings WHERE id = p_building_id;

  -- Remove population if community building
  IF v_building_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = GREATEST(COALESCE(population, 0) - v_building_info.provides_population, 0)
    WHERE id = v_player_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_building(integer) IS 'Remove a building from the town grid.';

-- Add population column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'population'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN population integer DEFAULT 0;
  END IF;
END $$;


-- Create storage management system with warehouse upgrades

-- Add storage capacity to profiles
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'storage_capacity'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN storage_capacity integer DEFAULT 50;
  END IF;
END $$;

-- Create warehouse_upgrades table
CREATE TABLE IF NOT EXISTS public.warehouse_upgrades (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 10),
  upgraded_at timestamptz DEFAULT now(),
  UNIQUE(player_id)
);

-- Enable RLS
ALTER TABLE public.warehouse_upgrades ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own upgrades
CREATE POLICY "Players can view own upgrades" ON public.warehouse_upgrades
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own upgrades" ON public.warehouse_upgrades
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own upgrades" ON public.warehouse_upgrades
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Initialize warehouse upgrade for existing players
INSERT INTO public.warehouse_upgrades (player_id, level)
SELECT id, 1 FROM public.profiles
ON CONFLICT (player_id) DO NOTHING;

-- Function to calculate storage capacity from level
CREATE OR REPLACE FUNCTION public.get_storage_capacity(p_level integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Base: 50, each level adds 25
  RETURN 50 + (p_level - 1) * 25;
END;
$$;

COMMENT ON FUNCTION public.get_storage_capacity(integer) IS 'Calculate storage capacity from warehouse level';

-- Function to upgrade warehouse
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

  -- Update storage capacity
  v_new_capacity := public.get_storage_capacity(v_new_level);
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

COMMENT ON FUNCTION public.upgrade_warehouse() IS 'Upgrade warehouse: increases storage capacity, costs crystals based on level';

-- Function to get current storage usage
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
  -- Get capacity
  SELECT storage_capacity INTO v_capacity
  FROM public.profiles
  WHERE id = p_player_id;

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

COMMENT ON FUNCTION public.get_storage_usage(uuid) IS 'Get current storage usage statistics for a player';


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


-- Create achievement system

-- Create achievements table (master list)
CREATE TABLE IF NOT EXISTS public.achievements (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  description text NOT NULL,
  category text NOT NULL CHECK (category IN ('farming', 'factory', 'city', 'social', 'general')),
  condition_type text NOT NULL, -- e.g., 'harvest_count', 'produce_count', 'build_count'
  condition_value integer NOT NULL, -- e.g., 100 harvests
  reward_crystals integer DEFAULT 0,
  reward_xp integer DEFAULT 0,
  reward_title text, -- e.g., "Master Farmer"
  icon text DEFAULT '🏆'
);

-- Create player_achievements table (progress tracking)
CREATE TABLE IF NOT EXISTS public.player_achievements (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_id integer NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  progress integer NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  claimed boolean NOT NULL DEFAULT false,
  claimed_at timestamptz,
  PRIMARY KEY (player_id, achievement_id)
);

-- Enable RLS
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view achievements
CREATE POLICY "Anyone can view achievements" ON public.achievements
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view own progress
CREATE POLICY "Players can view own achievements" ON public.player_achievements
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can update own achievements" ON public.player_achievements
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can insert own achievements" ON public.player_achievements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.player_achievements;

-- Seed achievements
INSERT INTO public.achievements (name, description, category, condition_type, condition_value, reward_crystals, reward_xp, reward_title, icon) VALUES
-- Farming achievements
('First Harvest', 'Harvest your first crop', 'farming', 'harvest_count', 1, 50, 10, null, '🌾'),
('Farmer', 'Harvest 10 crops', 'farming', 'harvest_count', 10, 100, 50, 'Farmer', '🌾'),
('Master Farmer', 'Harvest 100 crops', 'farming', 'harvest_count', 100, 500, 250, 'Master Farmer', '🌾'),
('Crop Collector', 'Harvest 5 different crop types', 'farming', 'crop_variety', 5, 200, 100, 'Crop Collector', '🌽'),
-- Factory achievements
('First Production', 'Complete your first factory production', 'factory', 'produce_count', 1, 50, 10, null, '⚙️'),
('Craftsman', 'Complete 50 factory productions', 'factory', 'produce_count', 50, 300, 150, 'Craftsman', '⚙️'),
('Master Craftsman', 'Complete 500 factory productions', 'factory', 'produce_count', 500, 2000, 1000, 'Master Craftsman', '⚙️'),
('Recipe Master', 'Unlock 5 different recipes', 'factory', 'recipe_variety', 5, 400, 200, 'Recipe Master', '📜'),
-- City achievements
('Builder', 'Place 5 buildings', 'city', 'build_count', 5, 200, 100, 'Builder', '🏗️'),
('Architect', 'Place 20 buildings', 'city', 'build_count', 20, 1000, 500, 'Architect', '🏛️'),
('Upgrader', 'Upgrade a building to level 3', 'city', 'upgrade_level', 3, 300, 150, 'Upgrader', '⬆️'),
-- Social achievements
('Helper', 'Help 10 friends', 'social', 'help_count', 10, 200, 100, 'Helper', '🤝'),
('Trader', 'Complete 10 trades', 'social', 'trade_count', 10, 300, 150, 'Trader', '💼'),
-- General achievements
('Level Up', 'Reach level 5', 'general', 'player_level', 5, 200, 100, null, '⭐'),
('Crystal Collector', 'Earn 1000 crystals', 'general', 'crystals_earned', 1000, 500, 250, 'Crystal Collector', '💎'),
('Daily Player', 'Claim daily reward 7 days in a row', 'general', 'daily_streak', 7, 500, 250, 'Daily Player', '📅'),
-- Mining achievements
('First Dig', 'Mine your first ore', 'general', 'mine_count', 1, 50, 10, null, '⛏️'),
('Miner', 'Mine 50 ores', 'general', 'mine_count', 50, 300, 150, 'Miner', '⛏️'),
('Master Miner', 'Mine 500 ores', 'general', 'mine_count', 500, 2000, 1000, 'Master Miner', '⛏️'),
('Deep Explorer', 'Reach depth 100', 'general', 'mine_depth', 100, 1000, 500, 'Deep Explorer', '🕳️')
ON CONFLICT (name) DO NOTHING;

-- Function to check and update achievements
CREATE OR REPLACE FUNCTION public.check_achievements(p_condition_type text, p_increment integer DEFAULT 1)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_achievement record;
  v_current_progress integer;
  v_new_progress integer;
BEGIN
  -- Find all achievements matching the condition type
  FOR v_achievement IN
    SELECT * FROM public.achievements
    WHERE condition_type = p_condition_type
  LOOP
    -- Get or create player achievement progress
    SELECT progress INTO v_current_progress
    FROM public.player_achievements
    WHERE player_id = v_player_id AND achievement_id = v_achievement.id;

    IF NOT FOUND THEN
      -- Create new progress entry
      INSERT INTO public.player_achievements (player_id, achievement_id, progress)
      VALUES (v_player_id, v_achievement.id, p_increment);
      v_new_progress := p_increment;
    ELSE
      -- Update progress
      v_new_progress := v_current_progress + p_increment;
      UPDATE public.player_achievements
      SET progress = v_new_progress
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id;
    END IF;

    -- Check if achievement is completed
    IF v_new_progress >= v_achievement.condition_value AND NOT EXISTS (
      SELECT 1 FROM public.player_achievements
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id AND completed = true
    ) THEN
      -- Mark as completed
      UPDATE public.player_achievements
      SET completed = true, completed_at = now()
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.check_achievements(text, integer) IS 'Check and update achievement progress for a condition type';

-- Function to claim achievement reward
CREATE OR REPLACE FUNCTION public.claim_achievement(p_achievement_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_achievement record;
  v_player_achievement record;
  v_result jsonb;
BEGIN
  -- Get achievement
  SELECT * INTO v_achievement
  FROM public.achievements
  WHERE id = p_achievement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Achievement % not found', p_achievement_id;
  END IF;

  -- Get player achievement
  SELECT * INTO v_player_achievement
  FROM public.player_achievements
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  IF NOT FOUND OR NOT v_player_achievement.completed THEN
    RAISE EXCEPTION 'Achievement % is not completed', p_achievement_id;
  END IF;

  IF v_player_achievement.claimed THEN
    RAISE EXCEPTION 'Achievement % reward already claimed', p_achievement_id;
  END IF;

  -- Award rewards
  IF v_achievement.reward_crystals > 0 THEN
    UPDATE public.profiles
    SET crystals = crystals + v_achievement.reward_crystals
    WHERE id = v_player_id;
  END IF;

  IF v_achievement.reward_xp > 0 THEN
    UPDATE public.profiles
    SET xp = xp + v_achievement.reward_xp
    WHERE id = v_player_id;
  END IF;

  -- Mark as claimed
  UPDATE public.player_achievements
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', v_achievement.reward_crystals,
    'xp_awarded', v_achievement.reward_xp,
    'title', v_achievement.reward_title
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_achievement(integer) IS 'Claim achievement reward: awards crystals, XP, and title';

-- Trigger to check achievements on harvest
CREATE OR REPLACE FUNCTION public.check_achievements_on_harvest()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.check_achievements('harvest_count', 1);
  RETURN NEW;
END;
$$;

-- Note: We'll call check_achievements manually from RPCs rather than using triggers
-- for better control and to avoid performance issues


-- Create quest system for tutorial, daily, and weekly quests

-- Create quests table (master list)
CREATE TABLE IF NOT EXISTS public.quests (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  type text NOT NULL CHECK (type IN ('tutorial', 'daily', 'weekly', 'story')),
  title text NOT NULL,
  description text NOT NULL,
  objectives jsonb NOT NULL, -- [{type: 'harvest', target: 5, current: 0}, ...]
  rewards jsonb NOT NULL, -- {crystals: 100, xp: 50, items: {item_id: quantity}}
  order_index integer DEFAULT 0, -- For tutorial/story ordering
  available boolean DEFAULT true
);

-- Create quest_progress table (player progress)
CREATE TABLE IF NOT EXISTS public.quest_progress (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  quest_id integer NOT NULL REFERENCES public.quests(id) ON DELETE CASCADE,
  progress jsonb NOT NULL, -- Same structure as objectives but with current values
  completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  claimed boolean NOT NULL DEFAULT false,
  claimed_at timestamptz,
  started_at timestamptz DEFAULT now(),
  expires_at timestamptz, -- For daily/weekly quests
  PRIMARY KEY (player_id, quest_id)
);

-- Enable RLS
ALTER TABLE public.quests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quest_progress ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view available quests
CREATE POLICY "Anyone can view quests" ON public.quests
  FOR SELECT TO authenticated
  USING (available = true);

-- Policy: Players can view own progress
CREATE POLICY "Players can view own quest progress" ON public.quest_progress
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can update own quest progress" ON public.quest_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can insert own quest progress" ON public.quest_progress
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.quest_progress;

-- Seed tutorial quests
INSERT INTO public.quests (name, type, title, description, objectives, rewards, order_index) VALUES
('tutorial_1', 'tutorial', 'Welcome to Eldergrove', 'Learn the basics of farming', 
 '[
   {"type": "harvest", "target": 1, "description": "Harvest 1 crop"}
 ]'::jsonb,
 '{"crystals": 100, "xp": 50}'::jsonb, 1),
('tutorial_2', 'tutorial', 'First Production', 'Create your first factory item',
 '[
   {"type": "produce", "target": 1, "description": "Complete 1 factory production"}
 ]'::jsonb,
 '{"crystals": 150, "xp": 75}'::jsonb, 2),
('tutorial_3', 'tutorial', 'Build Your Town', 'Place your first building',
 '[
   {"type": "build", "target": 1, "description": "Place 1 building"}
 ]'::jsonb,
 '{"crystals": 200, "xp": 100}'::jsonb, 3),
('tutorial_4', 'tutorial', 'Marketplace', 'Sell items at the marketplace',
 '[
   {"type": "sell", "target": 1, "description": "Sell 1 item"}
 ]'::jsonb,
 '{"crystals": 150, "xp": 75}'::jsonb, 4),
('tutorial_5', 'tutorial', 'Skyport Orders', 'Complete your first skyport order',
 '[
   {"type": "order", "target": 1, "description": "Complete 1 skyport order"}
 ]'::jsonb,
 '{"crystals": 250, "xp": 125}'::jsonb, 5)
ON CONFLICT (name) DO NOTHING;

-- Function to start a quest
CREATE OR REPLACE FUNCTION public.start_quest(p_quest_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_quest record;
  v_expires_at timestamptz;
BEGIN
  -- Get quest
  SELECT * INTO v_quest
  FROM public.quests
  WHERE id = p_quest_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest % not found or not available', p_quest_id;
  END IF;

  -- Check if already started
  IF EXISTS (
    SELECT 1 FROM public.quest_progress
    WHERE player_id = v_player_id AND quest_id = p_quest_id
  ) THEN
    RAISE EXCEPTION 'Quest % already started', p_quest_id;
  END IF;

  -- Calculate expiration for daily/weekly quests
  IF v_quest.type = 'daily' THEN
    v_expires_at := now() + interval '24 hours';
  ELSIF v_quest.type = 'weekly' THEN
    v_expires_at := now() + interval '7 days';
  ELSE
    v_expires_at := NULL;
  END IF;

  -- Initialize progress
  INSERT INTO public.quest_progress (player_id, quest_id, progress, expires_at)
  VALUES (v_player_id, p_quest_id, v_quest.objectives, v_expires_at);
END;
$$;

COMMENT ON FUNCTION public.start_quest(integer) IS 'Start a quest for the player';

-- Function to update quest progress
CREATE OR REPLACE FUNCTION public.update_quest_progress(
  p_objective_type text,
  p_quest_id integer DEFAULT NULL,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_progress jsonb;
  v_objective jsonb;
  v_current_value integer;
  v_target_value integer;
  v_all_completed boolean;
  v_idx integer;
  v_quest_progress record;
BEGIN
  -- Update all active quests if p_quest_id is NULL, otherwise update specific quest
  FOR v_quest_progress IN
    SELECT * FROM public.quest_progress
    WHERE player_id = v_player_id
      AND (p_quest_id IS NULL OR quest_id = p_quest_id)
      AND NOT completed
      AND (expires_at IS NULL OR expires_at > now())
  LOOP
    v_progress := v_quest_progress.progress;

  -- Update progress for matching objective type
  FOR v_idx IN 0..jsonb_array_length(v_progress) - 1 LOOP
    v_objective := v_progress->v_idx;
    
    IF (v_objective->>'type') = p_objective_type THEN
      v_current_value := COALESCE((v_objective->>'current')::integer, 0);
      v_target_value := (v_objective->>'target')::integer;
      
      v_current_value := LEAST(v_current_value + p_increment, v_target_value);
      
      v_progress := jsonb_set(
        v_progress,
        ARRAY[v_idx::text, 'current'],
        v_current_value::jsonb
      );
    END IF;
  END LOOP;

  -- Check if all objectives completed
  v_all_completed := true;
  FOR v_idx IN 0..jsonb_array_length(v_progress) - 1 LOOP
    v_objective := v_progress->v_idx;
    v_current_value := COALESCE((v_objective->>'current')::integer, 0);
    v_target_value := (v_objective->>'target')::integer;
    
    IF v_current_value < v_target_value THEN
      v_all_completed := false;
      EXIT;
    END IF;
  END LOOP;

    -- Update progress
    UPDATE public.quest_progress
    SET progress = v_progress,
        completed = CASE WHEN v_all_completed THEN true ELSE completed END,
        completed_at = CASE WHEN v_all_completed AND NOT completed THEN now() ELSE completed_at END
    WHERE player_id = v_player_id AND quest_id = v_quest_progress.quest_id;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.update_quest_progress(text, integer, integer) IS 'Update quest progress for a specific objective type';

-- Function to claim quest reward
CREATE OR REPLACE FUNCTION public.claim_quest_reward(p_quest_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_quest record;
  v_progress record;
  v_rewards jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_qty integer;
  v_result jsonb;
BEGIN
  -- Get quest
  SELECT * INTO v_quest
  FROM public.quests
  WHERE id = p_quest_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest % not found', p_quest_id;
  END IF;

  -- Get progress
  SELECT * INTO v_progress
  FROM public.quest_progress
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  IF NOT FOUND OR NOT v_progress.completed THEN
    RAISE EXCEPTION 'Quest % is not completed', p_quest_id;
  END IF;

  IF v_progress.claimed THEN
    RAISE EXCEPTION 'Quest % reward already claimed', p_quest_id;
  END IF;

  v_rewards := v_quest.rewards;

  -- Award crystals
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_rewards->>'crystals')::integer
    WHERE id = v_player_id;
  END IF;

  -- Award XP
  IF v_rewards ? 'xp' THEN
    UPDATE public.profiles
    SET xp = xp + (v_rewards->>'xp')::integer
    WHERE id = v_player_id;
  END IF;

  -- Award items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark as claimed
  UPDATE public.quest_progress
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE((v_rewards->>'crystals')::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_quest_reward(integer) IS 'Claim quest reward: awards crystals, XP, and items';

-- Function to generate daily quests
CREATE OR REPLACE FUNCTION public.generate_daily_quests(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_quest record;
BEGIN
  -- Delete expired daily quests
  DELETE FROM public.quest_progress
  WHERE player_id = p_player_id
    AND quest_id IN (SELECT id FROM public.quests WHERE type = 'daily')
    AND expires_at < now();

  -- Generate new daily quests (3 per day)
  FOR v_quest IN
    SELECT * FROM public.quests
    WHERE type = 'daily' AND available = true
    ORDER BY random()
    LIMIT 3
  LOOP
    -- Only add if not already active
    IF NOT EXISTS (
      SELECT 1 FROM public.quest_progress
      WHERE player_id = p_player_id AND quest_id = v_quest.id
    ) THEN
      INSERT INTO public.quest_progress (player_id, quest_id, progress, expires_at)
      VALUES (p_player_id, v_quest.id, v_quest.objectives, now() + interval '24 hours')
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.generate_daily_quests(uuid) IS 'Generate daily quests for a player';


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
CREATE POLICY "Anyone can view animal types" ON public.animal_types
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view and manage own enclosures
CREATE POLICY "Players can view own enclosures" ON public.zoo_enclosures
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own enclosures" ON public.zoo_enclosures
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own enclosures" ON public.zoo_enclosures
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own enclosures" ON public.zoo_enclosures
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.zoo_enclosures;

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
    WHERE id = p_enclosure_id;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_id = p_animal_type_id,
        animal2_produced_at = now()
    WHERE id = p_enclosure_id;
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


-- Create friend/neighbor system for social features

-- Create friends table
CREATE TABLE IF NOT EXISTS public.friends (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('pending', 'accepted', 'blocked')),
  requested_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  UNIQUE(player_id, friend_id)
);

-- Create friend_help table (track help given/received)
CREATE TABLE IF NOT EXISTS public.friend_help (
  id serial PRIMARY KEY,
  helper_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  helped_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  help_type text NOT NULL CHECK (help_type IN ('speed_production', 'fill_order', 'water_crops')),
  target_id integer, -- factory_id, order_id, or plot_index depending on help_type
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_help ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view their own friendships
CREATE POLICY "Players can view own friendships" ON public.friends
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can insert own friend requests" ON public.friends
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can update own friendships" ON public.friends
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id)
  WITH CHECK (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can delete own friendships" ON public.friends
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id);

-- Policy: Players can view help they gave/received
CREATE POLICY "Players can view own help" ON public.friend_help
  FOR SELECT TO authenticated
  USING (auth.uid() = helper_id OR auth.uid() = helped_id);

CREATE POLICY "Players can insert own help" ON public.friend_help
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = helper_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.friends;
ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_help;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_friends_player ON public.friends(player_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend ON public.friends(friend_id);
CREATE INDEX IF NOT EXISTS idx_friends_status ON public.friends(status);
CREATE INDEX IF NOT EXISTS idx_friend_help_helper ON public.friend_help(helper_id);
CREATE INDEX IF NOT EXISTS idx_friend_help_helped ON public.friend_help(helped_id);

-- Function to send friend request
CREATE OR REPLACE FUNCTION public.send_friend_request(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  IF v_player_id = p_friend_id THEN
    RAISE EXCEPTION 'Cannot send friend request to yourself';
  END IF;

  -- Check if already friends or request exists
  IF EXISTS (
    SELECT 1 FROM public.friends
    WHERE (player_id = v_player_id AND friend_id = p_friend_id)
       OR (player_id = p_friend_id AND friend_id = v_player_id)
  ) THEN
    RAISE EXCEPTION 'Friend request already exists or already friends';
  END IF;

  -- Create friend request (bidirectional)
  INSERT INTO public.friends (player_id, friend_id, status, requested_by)
  VALUES (v_player_id, p_friend_id, 'pending', v_player_id),
         (p_friend_id, v_player_id, 'pending', v_player_id);
END;
$$;

COMMENT ON FUNCTION public.send_friend_request(uuid) IS 'Send a friend request to another player';

-- Function to accept friend request
CREATE OR REPLACE FUNCTION public.accept_friend_request(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  -- Check if request exists
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE player_id = v_player_id
      AND friend_id = p_friend_id
      AND status = 'pending'
      AND requested_by != v_player_id
  ) THEN
    RAISE EXCEPTION 'No pending friend request from %', p_friend_id;
  END IF;

  -- Accept both directions
  UPDATE public.friends
  SET status = 'accepted',
      accepted_at = now()
  WHERE (player_id = v_player_id AND friend_id = p_friend_id)
     OR (player_id = p_friend_id AND friend_id = v_player_id);
END;
$$;

COMMENT ON FUNCTION public.accept_friend_request(uuid) IS 'Accept a friend request';

-- Function to remove friend
CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  DELETE FROM public.friends
  WHERE (player_id = v_player_id AND friend_id = p_friend_id)
     OR (player_id = p_friend_id AND friend_id = v_player_id);
END;
$$;

COMMENT ON FUNCTION public.remove_friend(uuid) IS 'Remove a friend (both directions)';

-- Function to help friend speed up production
CREATE OR REPLACE FUNCTION public.help_friend_speed_production(
  p_friend_id uuid,
  p_factory_type text,
  p_slot integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_queue_item record;
  v_speedup_minutes integer := 30; -- Reduce by 30 minutes
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get queue item
  SELECT * INTO v_queue_item
  FROM public.factory_queue
  WHERE player_id = p_friend_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Production slot not found';
  END IF;

  -- Speed up production
  UPDATE public.factory_queue
  SET finishes_at = GREATEST(finishes_at - (v_speedup_minutes || ' minutes')::interval, now())
  WHERE player_id = p_friend_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  -- Record help
  INSERT INTO public.friend_help (helper_id, helped_id, help_type, target_id)
  VALUES (v_player_id, p_friend_id, 'speed_production', p_slot);

  -- Check achievements
  PERFORM public.check_achievements('help_count', 1);
END;
$$;

COMMENT ON FUNCTION public.help_friend_speed_production(uuid, text, integer) IS 'Help a friend by speeding up their factory production';

-- Function to help friend fill order
CREATE OR REPLACE FUNCTION public.help_friend_fill_order(
  p_friend_id uuid,
  p_order_id integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = p_friend_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order already completed';
  END IF;

  v_requirements := v_order.requirements;

  -- Check and deduct items from helper's inventory
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
    v_item_id := v_key::integer;
    v_required_qty := v_value::integer;

    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_required_qty THEN
      RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
    END IF;

    -- Deduct from helper's inventory
    UPDATE public.inventory
    SET quantity = quantity - v_required_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Mark order as completed (friend gets rewards)
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Award rewards to friend
  IF v_order.rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_order.rewards->>'crystals')::integer,
        xp = xp + COALESCE((v_order.rewards->>'xp')::integer, 0)
    WHERE id = p_friend_id;
  END IF;

  -- Record help
  INSERT INTO public.friend_help (helper_id, helped_id, help_type, target_id)
  VALUES (v_player_id, p_friend_id, 'fill_order', p_order_id);

  -- Check achievements
  PERFORM public.check_achievements('help_count', 1);
END;
$$;

COMMENT ON FUNCTION public.help_friend_fill_order(uuid, integer) IS 'Help a friend by filling their skyport order';

-- Function to get friend's town data (read-only)
CREATE OR REPLACE FUNCTION public.visit_friend_town(p_friend_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_buildings jsonb;
  v_result jsonb;
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get buildings (read-only)
  SELECT jsonb_agg(row_to_json(b))
  INTO v_buildings
  FROM (
    SELECT building_type, grid_x, grid_y, level
    FROM public.buildings
    WHERE player_id = p_friend_id
  ) b;

  -- Return read-only town data
  SELECT jsonb_build_object(
    'buildings', COALESCE(v_buildings, '[]'::jsonb),
    'friend_id', p_friend_id
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.visit_friend_town(uuid) IS 'Visit a friend''s town (read-only view)';


-- Create market box (player trading) system

-- Create market_listings table
CREATE TABLE IF NOT EXISTS public.market_listings (
  id serial PRIMARY KEY,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id integer NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  price_crystals integer NOT NULL CHECK (price_crystals > 0),
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz NOT NULL,
  purchased_at timestamptz,
  buyer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- Enable RLS
ALTER TABLE public.market_listings ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view active listings
CREATE POLICY "Anyone can view active listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (purchased_at IS NULL AND expires_at > now());

-- Policy: Players can view their own listings
CREATE POLICY "Players can view own listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (auth.uid() = seller_id);

-- Policy: Players can create listings
CREATE POLICY "Players can create listings" ON public.market_listings
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id);

-- Policy: Players can update own listings
CREATE POLICY "Players can update own listings" ON public.market_listings
  FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id)
  WITH CHECK (auth.uid() = seller_id);

-- Policy: Players can delete own listings
CREATE POLICY "Players can delete own listings" ON public.market_listings
  FOR DELETE TO authenticated
  USING (auth.uid() = seller_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.market_listings;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_market_listings_seller ON public.market_listings(seller_id);
CREATE INDEX IF NOT EXISTS idx_market_listings_active ON public.market_listings(purchased_at, expires_at) WHERE purchased_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_market_listings_item ON public.market_listings(item_id);

-- Function to create a listing
CREATE OR REPLACE FUNCTION public.create_listing(
  p_item_id integer,
  p_quantity integer,
  p_price_crystals integer,
  p_expires_hours integer DEFAULT 24
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_qty bigint;
  v_listing_id integer;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  IF p_price_crystals <= 0 THEN
    RAISE EXCEPTION 'Price must be positive';
  END IF;

  -- Check inventory
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient item %: required %, available %', p_item_id, p_quantity, v_current_qty;
  END IF;

  -- Deduct from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Create listing
  INSERT INTO public.market_listings (
    seller_id,
    item_id,
    quantity,
    price_crystals,
    expires_at
  )
  VALUES (
    v_player_id,
    p_item_id,
    p_quantity,
    p_price_crystals,
    now() + (p_expires_hours || ' hours')::interval
  )
  RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$;

COMMENT ON FUNCTION public.create_listing(integer, integer, integer, integer) IS 'Create a market listing: deducts items from inventory, creates listing';

-- Function to purchase a listing
CREATE OR REPLACE FUNCTION public.purchase_listing(p_listing_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id uuid := auth.uid();
  v_listing record;
  v_total_cost integer;
  v_buyer_crystals bigint;
  v_seller_crystals bigint;
  v_commission integer;
  v_seller_profit integer;
  v_result jsonb;
BEGIN
  -- Get listing
  SELECT * INTO v_listing
  FROM public.market_listings
  WHERE id = p_listing_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % not found', p_listing_id;
  END IF;

  IF v_listing.purchased_at IS NOT NULL THEN
    RAISE EXCEPTION 'Listing % already purchased', p_listing_id;
  END IF;

  IF v_listing.expires_at < now() THEN
    RAISE EXCEPTION 'Listing % has expired', p_listing_id;
  END IF;

  IF v_listing.seller_id = v_buyer_id THEN
    RAISE EXCEPTION 'Cannot purchase your own listing';
  END IF;

  v_total_cost := v_listing.price_crystals;

  -- Check buyer crystals
  SELECT crystals INTO v_buyer_crystals
  FROM public.profiles
  WHERE id = v_buyer_id;

  IF v_buyer_crystals < v_total_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_total_cost, v_buyer_crystals;
  END IF;

  -- Calculate commission (5%)
  v_commission := FLOOR(v_total_cost * 0.05);
  v_seller_profit := v_total_cost - v_commission;

  -- Deduct crystals from buyer
  UPDATE public.profiles
  SET crystals = crystals - v_total_cost
  WHERE id = v_buyer_id;

  -- Add profit to seller
  UPDATE public.profiles
  SET crystals = crystals + v_seller_profit
  WHERE id = v_listing.seller_id;

  -- Add items to buyer inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_buyer_id, v_listing.item_id, v_listing.quantity::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Mark listing as purchased
  UPDATE public.market_listings
  SET purchased_at = now(),
      buyer_id = v_buyer_id
  WHERE id = p_listing_id;

  -- Check achievements
  PERFORM public.check_achievements('trade_count', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'item_id', v_listing.item_id,
    'quantity', v_listing.quantity,
    'cost', v_total_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_listing(integer) IS 'Purchase a market listing: transfers crystals and items, applies 5% commission';

-- Function to cancel a listing
CREATE OR REPLACE FUNCTION public.cancel_listing(p_listing_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_listing record;
BEGIN
  -- Get listing
  SELECT * INTO v_listing
  FROM public.market_listings
  WHERE id = p_listing_id AND seller_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % not found or does not belong to you', p_listing_id;
  END IF;

  IF v_listing.purchased_at IS NOT NULL THEN
    RAISE EXCEPTION 'Listing % already purchased', p_listing_id;
  END IF;

  -- Return items to inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_listing.item_id, v_listing.quantity::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Delete listing
  DELETE FROM public.market_listings WHERE id = p_listing_id;
END;
$$;

COMMENT ON FUNCTION public.cancel_listing(integer) IS 'Cancel a listing: returns items to seller inventory';


-- Create co-op tasks system for coven enhancements

-- Create coven_tasks table
CREATE TABLE IF NOT EXISTS public.coven_tasks (
  id serial PRIMARY KEY,
  coven_id uuid NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NOT NULL,
  objectives jsonb NOT NULL, -- [{type: 'produce', target: 1000, item: 'bread'}, ...]
  rewards jsonb NOT NULL, -- {coven_points: 100, shared_crystals: 500}
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz,
  completed boolean DEFAULT false,
  completed_at timestamptz
);

-- Create coven_task_progress table
CREATE TABLE IF NOT EXISTS public.coven_task_progress (
  task_id integer NOT NULL REFERENCES public.coven_tasks(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  contribution jsonb NOT NULL, -- Same structure as objectives but with current values
  contributed_at timestamptz DEFAULT now(),
  PRIMARY KEY (task_id, player_id)
);

-- Enable RLS
ALTER TABLE public.coven_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coven_task_progress ENABLE ROW LEVEL SECURITY;

-- Policy: Coven members can view coven tasks
CREATE POLICY "Coven members can view tasks" ON public.coven_tasks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
    )
  );

-- Policy: Leaders and elders can create tasks
CREATE POLICY "Leaders and elders can create tasks" ON public.coven_tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
        AND role IN ('leader', 'elder')
    )
  );

-- Policy: Leaders and elders can update tasks
CREATE POLICY "Leaders and elders can update tasks" ON public.coven_tasks
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
        AND role IN ('leader', 'elder')
    )
  );

-- Policy: Coven members can view task progress
CREATE POLICY "Coven members can view task progress" ON public.coven_task_progress
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      JOIN public.coven_tasks ct ON ct.coven_id = cm.coven_id
      WHERE ct.id = coven_task_progress.task_id
        AND cm.player_id = auth.uid()
    )
  );

-- Policy: Coven members can contribute to tasks
CREATE POLICY "Coven members can contribute to tasks" ON public.coven_task_progress
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = player_id AND
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      JOIN public.coven_tasks ct ON ct.coven_id = cm.coven_id
      WHERE ct.id = coven_task_progress.task_id
        AND cm.player_id = auth.uid()
    )
  );

CREATE POLICY "Coven members can update own contributions" ON public.coven_task_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.coven_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.coven_task_progress;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_coven_tasks_coven ON public.coven_tasks(coven_id);
CREATE INDEX IF NOT EXISTS idx_coven_tasks_completed ON public.coven_tasks(completed);
CREATE INDEX IF NOT EXISTS idx_coven_task_progress_task ON public.coven_task_progress(task_id);
CREATE INDEX IF NOT EXISTS idx_coven_task_progress_player ON public.coven_task_progress(player_id);

-- Function to create a coven task
CREATE OR REPLACE FUNCTION public.create_coven_task(
  p_coven_id uuid,
  p_name text,
  p_description text,
  p_objectives jsonb,
  p_rewards jsonb,
  p_expires_hours integer DEFAULT 168 -- Default 7 days
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_member_role text;
  v_task_id integer;
BEGIN
  -- Check if player is leader or elder
  SELECT role INTO v_member_role
  FROM public.coven_members
  WHERE coven_id = p_coven_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not a member of this coven';
  END IF;

  IF v_member_role NOT IN ('leader', 'elder') THEN
    RAISE EXCEPTION 'Only leaders and elders can create tasks';
  END IF;

  -- Create task
  INSERT INTO public.coven_tasks (
    coven_id,
    name,
    description,
    objectives,
    rewards,
    created_by,
    expires_at
  )
  VALUES (
    p_coven_id,
    p_name,
    p_description,
    p_objectives,
    p_rewards,
    v_player_id,
    now() + (p_expires_hours || ' hours')::interval
  )
  RETURNING id INTO v_task_id;

  RETURN v_task_id;
END;
$$;

COMMENT ON FUNCTION public.create_coven_task(uuid, text, text, jsonb, jsonb, integer) IS 'Create a coven task (leaders and elders only)';

-- Function to contribute to a coven task
CREATE OR REPLACE FUNCTION public.contribute_to_task(
  p_task_id integer,
  p_objective_type text,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_task record;
  v_progress record;
  v_contribution jsonb;
  v_objective jsonb;
  v_current_value integer;
  v_target_value integer;
  v_idx integer;
  v_total_progress jsonb;
  v_all_completed boolean;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM public.coven_tasks
  WHERE id = p_task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % not found', p_task_id;
  END IF;

  -- Check if player is member of coven
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = v_task.coven_id AND player_id = v_player_id
  ) THEN
    RAISE EXCEPTION 'You are not a member of this coven';
  END IF;

  IF v_task.completed THEN
    RAISE EXCEPTION 'Task % is already completed', p_task_id;
  END IF;

  IF v_task.expires_at < now() THEN
    RAISE EXCEPTION 'Task % has expired', p_task_id;
  END IF;

  -- Get or create progress
  SELECT * INTO v_progress
  FROM public.coven_task_progress
  WHERE task_id = p_task_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    -- Initialize with zeros
    v_contribution := v_task.objectives;
    FOR v_idx IN 0..jsonb_array_length(v_contribution) - 1 LOOP
      v_contribution := jsonb_set(
        v_contribution,
        ARRAY[v_idx::text, 'current'],
        0::jsonb
      );
    END LOOP;
    
    INSERT INTO public.coven_task_progress (task_id, player_id, contribution)
    VALUES (p_task_id, v_player_id, v_contribution);
    
    v_progress.contribution := v_contribution;
  END IF;

  v_contribution := v_progress.contribution;

  -- Update contribution for matching objective type
  FOR v_idx IN 0..jsonb_array_length(v_contribution) - 1 LOOP
    v_objective := v_contribution->v_idx;
    
    IF (v_objective->>'type') = p_objective_type THEN
      v_current_value := COALESCE((v_objective->>'current')::integer, 0);
      v_target_value := (v_objective->>'target')::integer;
      
      v_current_value := LEAST(v_current_value + p_increment, v_target_value);
      
      v_contribution := jsonb_set(
        v_contribution,
        ARRAY[v_idx::text, 'current'],
        v_current_value::jsonb
      );
    END IF;
  END LOOP;

  -- Update progress
  UPDATE public.coven_task_progress
  SET contribution = v_contribution,
      contributed_at = now()
  WHERE task_id = p_task_id AND player_id = v_player_id;

  -- Calculate total progress across all members (simplified check)

  -- Check if all objectives completed
  v_all_completed := true;
  FOR v_idx IN 0..jsonb_array_length(v_task.objectives) - 1 LOOP
    v_objective := v_task.objectives->v_idx;
    v_target_value := (v_objective->>'target')::integer;
    
    -- Sum contributions from all members for this objective type
    SELECT COALESCE(SUM((elem->>'current')::integer), 0) INTO v_current_value
    FROM public.coven_task_progress,
    LATERAL jsonb_array_elements(contribution) elem
    WHERE task_id = p_task_id
      AND (elem->>'type') = (v_objective->>'type');
    
    IF v_current_value < v_target_value THEN
      v_all_completed := false;
      EXIT;
    END IF;
  END LOOP;

  -- Mark task as completed if all objectives met
  IF v_all_completed AND NOT v_task.completed THEN
    UPDATE public.coven_tasks
    SET completed = true,
        completed_at = now()
    WHERE id = p_task_id;

    -- Award rewards to coven
    IF v_task.rewards ? 'shared_crystals' THEN
      UPDATE public.coven_resources
      SET crystals = crystals + (v_task.rewards->>'shared_crystals')::bigint
      WHERE coven_id = v_task.coven_id;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.contribute_to_task(integer, text, integer) IS 'Contribute to a coven task: updates player progress and checks for completion';

-- Function to claim task rewards (distribute to members)
CREATE OR REPLACE FUNCTION public.claim_coven_task_rewards(p_task_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_task record;
  v_member_count integer;
  v_crystals_per_member bigint;
  v_member record;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM public.coven_tasks
  WHERE id = p_task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % not found', p_task_id;
  END IF;

  -- Check if player is leader or elder
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = v_task.coven_id
      AND player_id = v_player_id
      AND role IN ('leader', 'elder')
  ) THEN
    RAISE EXCEPTION 'Only leaders and elders can claim rewards';
  END IF;

  IF NOT v_task.completed THEN
    RAISE EXCEPTION 'Task % is not completed', p_task_id;
  END IF;

  -- Get member count
  SELECT count(*) INTO v_member_count
  FROM public.coven_members
  WHERE coven_id = v_task.coven_id;

  -- Distribute shared crystals
  IF v_task.rewards ? 'shared_crystals' AND v_member_count > 0 THEN
    v_crystals_per_member := (v_task.rewards->>'shared_crystals')::bigint / v_member_count;

    -- Award to all members
    FOR v_member IN
      SELECT player_id FROM public.coven_members WHERE coven_id = v_task.coven_id
    LOOP
      UPDATE public.profiles
      SET crystals = crystals + v_crystals_per_member
      WHERE id = v_member.player_id;
    END LOOP;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.claim_coven_task_rewards(integer) IS 'Claim and distribute coven task rewards to all members';

-- Helper function to auto-contribute to active coven tasks
CREATE OR REPLACE FUNCTION public.auto_contribute_coven_tasks(
  p_objective_type text,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_coven_id uuid;
  v_task record;
BEGIN
  -- Get player's coven
  SELECT coven_id INTO v_coven_id
  FROM public.coven_members
  WHERE player_id = v_player_id
  LIMIT 1;

  IF v_coven_id IS NULL THEN
    RETURN; -- Not in a coven, silently exit
  END IF;

  -- Find active tasks for this coven
  FOR v_task IN
    SELECT * FROM public.coven_tasks
    WHERE coven_id = v_coven_id
      AND completed = false
      AND (expires_at IS NULL OR expires_at > now())
  LOOP
    -- Check if task has this objective type
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_task.objectives) obj
      WHERE (obj->>'type') = p_objective_type
    ) THEN
      -- Contribute to task
      PERFORM public.contribute_to_task(v_task.id, p_objective_type, p_increment);
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.auto_contribute_coven_tasks(text, integer) IS 'Automatically contribute to active coven tasks for the player';


-- Create regatta competitions system (weekly competitive events)

-- Create regatta_events table
CREATE TABLE IF NOT EXISTS public.regatta_events (
  id serial PRIMARY KEY,
  name text NOT NULL,
  start_date timestamptz NOT NULL,
  end_date timestamptz NOT NULL,
  tasks jsonb NOT NULL, -- [{type: 'produce', target: 1000, item: 'bread'}, ...]
  rewards jsonb NOT NULL, -- {top_10: {crystals: 1000}, top_25: {crystals: 500}, participation: {crystals: 100}}
  status text DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'active', 'completed')),
  created_at timestamptz DEFAULT now()
);

-- Create regatta_participants table
CREATE TABLE IF NOT EXISTS public.regatta_participants (
  regatta_id integer NOT NULL REFERENCES public.regatta_events(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  coven_id uuid REFERENCES public.coven(id) ON DELETE SET NULL,
  points integer DEFAULT 0,
  tasks_completed jsonb DEFAULT '[]'::jsonb, -- Array of completed task IDs
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (regatta_id, player_id)
);

-- Create regatta_task_submissions table
CREATE TABLE IF NOT EXISTS public.regatta_task_submissions (
  id serial PRIMARY KEY,
  regatta_id integer NOT NULL REFERENCES public.regatta_events(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  task_index integer NOT NULL, -- Index in the tasks array
  submitted_at timestamptz DEFAULT now(),
  points_awarded integer DEFAULT 0,
  UNIQUE(regatta_id, player_id, task_index)
);

-- Enable RLS
ALTER TABLE public.regatta_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regatta_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regatta_task_submissions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view active/upcoming regattas
CREATE POLICY "Anyone can view regattas" ON public.regatta_events
  FOR SELECT TO authenticated
  USING (status IN ('upcoming', 'active'));

-- Policy: Players can view own participation
CREATE POLICY "Players can view own participation" ON public.regatta_participants
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id OR EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = regatta_participants.coven_id AND player_id = auth.uid()
  ));

CREATE POLICY "Players can insert own participation" ON public.regatta_participants
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own participation" ON public.regatta_participants
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Policy: Players can view own submissions
CREATE POLICY "Players can view own submissions" ON public.regatta_task_submissions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own submissions" ON public.regatta_task_submissions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_task_submissions;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_regatta_events_status ON public.regatta_events(status);
CREATE INDEX IF NOT EXISTS idx_regatta_events_dates ON public.regatta_events(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_regatta ON public.regatta_participants(regatta_id);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_points ON public.regatta_participants(regatta_id, points DESC);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_coven ON public.regatta_participants(regatta_id, coven_id, points DESC);

-- Function to join regatta
CREATE OR REPLACE FUNCTION public.join_regatta(p_regatta_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_coven_id uuid;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'active' THEN
    RAISE EXCEPTION 'Regatta % is not active', p_regatta_id;
  END IF;

  IF now() < v_regatta.start_date OR now() > v_regatta.end_date THEN
    RAISE EXCEPTION 'Regatta % is not currently running', p_regatta_id;
  END IF;

  -- Check if already joined
  IF EXISTS (
    SELECT 1 FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id AND player_id = v_player_id
  ) THEN
    RAISE EXCEPTION 'Already joined regatta %', p_regatta_id;
  END IF;

  -- Get player's coven (optional)
  SELECT coven_id INTO v_coven_id
  FROM public.coven_members
  WHERE player_id = v_player_id
  LIMIT 1;

  -- Join regatta
  INSERT INTO public.regatta_participants (regatta_id, player_id, coven_id, points)
  VALUES (p_regatta_id, v_player_id, v_coven_id, 0);
END;
$$;

COMMENT ON FUNCTION public.join_regatta(integer) IS 'Join an active regatta competition';

-- Function to submit regatta task
CREATE OR REPLACE FUNCTION public.submit_regatta_task(
  p_regatta_id integer,
  p_task_index integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_participant record;
  v_task jsonb;
  v_points integer;
  v_result jsonb;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'active' THEN
    RAISE EXCEPTION 'Regatta % is not active', p_regatta_id;
  END IF;

  -- Get participant
  SELECT * INTO v_participant
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You have not joined regatta %', p_regatta_id;
  END IF;

  -- Check if already submitted
  IF EXISTS (
    SELECT 1 FROM public.regatta_task_submissions
    WHERE regatta_id = p_regatta_id
      AND player_id = v_player_id
      AND task_index = p_task_index
  ) THEN
    RAISE EXCEPTION 'Task % already submitted', p_task_index;
  END IF;

  -- Get task
  SELECT value INTO v_task
  FROM jsonb_array_elements(v_regatta.tasks) WITH ORDINALITY AS t(value, idx)
  WHERE idx - 1 = p_task_index;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task index % not found', p_task_index;
  END IF;

  -- Calculate points (based on task difficulty)
  v_points := COALESCE((v_task->>'points')::integer, 100);

  -- Record submission
  INSERT INTO public.regatta_task_submissions (regatta_id, player_id, task_index, points_awarded)
  VALUES (p_regatta_id, v_player_id, p_task_index, v_points);

  -- Update participant points
  UPDATE public.regatta_participants
  SET points = points + v_points,
      tasks_completed = tasks_completed || jsonb_build_array(p_task_index)
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'points_awarded', v_points,
    'total_points', v_participant.points + v_points
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.submit_regatta_task(integer, integer) IS 'Submit completion of a regatta task';

-- Function to get regatta leaderboard
CREATE OR REPLACE FUNCTION public.get_regatta_leaderboard(
  p_regatta_id integer,
  p_leaderboard_type text DEFAULT 'global' -- 'global' or 'coven'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_leaderboard_type = 'coven' THEN
    -- Coven leaderboard
    SELECT jsonb_agg(
      jsonb_build_object(
        'coven_id', coven_id,
        'coven_name', (SELECT name FROM public.coven WHERE id = coven_id),
        'total_points', SUM(points),
        'member_count', count(*)
      ) ORDER BY SUM(points) DESC
    )
    INTO v_result
    FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id
      AND coven_id IS NOT NULL
    GROUP BY coven_id;
  ELSE
    -- Global leaderboard
    SELECT jsonb_agg(
      jsonb_build_object(
        'player_id', player_id,
        'username', (SELECT username FROM public.profiles WHERE id = player_id),
        'points', points,
        'coven_id', coven_id,
        'coven_name', CASE WHEN coven_id IS NOT NULL THEN (SELECT name FROM public.coven WHERE id = coven_id) ELSE NULL END
      ) ORDER BY points DESC
    )
    INTO v_result
    FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id
    ORDER BY points DESC
    LIMIT 100;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.get_regatta_leaderboard(integer, text) IS 'Get regatta leaderboard (global or coven)';

-- Function to claim regatta rewards
CREATE OR REPLACE FUNCTION public.claim_regatta_rewards(p_regatta_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_participant record;
  v_total_participants integer;
  v_player_rank integer;
  v_reward jsonb;
  v_crystals integer;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'completed' THEN
    RAISE EXCEPTION 'Regatta % is not completed yet', p_regatta_id;
  END IF;

  -- Get participant
  SELECT * INTO v_participant
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You did not participate in regatta %', p_regatta_id;
  END IF;

  -- Calculate rank
  SELECT count(*) INTO v_total_participants
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id;

  SELECT count(*) + 1 INTO v_player_rank
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id
    AND points > v_participant.points;

  -- Determine reward tier
  IF v_player_rank <= v_total_participants * 0.1 THEN
    -- Top 10%
    v_reward := v_regatta.rewards->'top_10';
  ELSIF v_player_rank <= v_total_participants * 0.25 THEN
    -- Top 25%
    v_reward := v_regatta.rewards->'top_25';
  ELSE
    -- Participation
    v_reward := v_regatta.rewards->'participation';
  END IF;

  -- Award crystals
  IF v_reward ? 'crystals' THEN
    v_crystals := (v_reward->>'crystals')::integer;
    UPDATE public.profiles
    SET crystals = crystals + v_crystals
    WHERE id = v_player_id;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'rank', v_player_rank,
    'total_participants', v_total_participants,
    'crystals_awarded', v_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.claim_regatta_rewards(integer) IS 'Claim regatta rewards based on final rank';

-- Function to create weekly regatta (to be called by cron or admin)
CREATE OR REPLACE FUNCTION public.create_weekly_regatta()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_regatta_id integer;
  v_start_date timestamptz;
  v_end_date timestamptz;
BEGIN
  -- Start next Monday, end next Sunday
  v_start_date := date_trunc('week', now() + interval '1 week') + interval '1 day'; -- Monday
  v_end_date := v_start_date + interval '6 days'; -- Sunday

  -- Create regatta with default tasks
  INSERT INTO public.regatta_events (
    name,
    start_date,
    end_date,
    tasks,
    rewards,
    status
  )
  VALUES (
    'Weekly Regatta - ' || to_char(v_start_date, 'Month YYYY'),
    v_start_date,
    v_end_date,
    '[
      {"type": "produce", "target": 100, "item": "bread", "points": 50},
      {"type": "harvest", "target": 200, "points": 30},
      {"type": "mine", "target": 50, "points": 40},
      {"type": "order", "target": 10, "points": 60}
    ]'::jsonb,
    '{
      "top_10": {"crystals": 2000},
      "top_25": {"crystals": 1000},
      "participation": {"crystals": 200}
    }'::jsonb,
    'upcoming'
  )
  RETURNING id INTO v_regatta_id;

  RETURN v_regatta_id;
END;
$$;

COMMENT ON FUNCTION public.create_weekly_regatta() IS 'Create a weekly regatta event (to be called by cron)';


-- Add population requirements system for building unlocks

-- Add population_required column to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS population_required integer DEFAULT 0;

-- Update existing building types with population requirements
UPDATE public.building_types
SET population_required = CASE
  WHEN building_type = 'bakery' THEN 0
  WHEN building_type = 'mill' THEN 0
  WHEN building_type = 'dairy' THEN 10
  WHEN building_type = 'textile' THEN 20
  WHEN building_type = 'smithy' THEN 30
  WHEN building_type = 'library' THEN 50
  WHEN building_type = 'market' THEN 15
  WHEN building_type = 'town_hall' THEN 100
  WHEN building_type = 'park' THEN 0
  WHEN building_type = 'fountain' THEN 0
  ELSE 0
END
WHERE population_required IS NULL OR population_required = 0;

-- Function to calculate total population from buildings
CREATE OR REPLACE FUNCTION public.calculate_population(p_player_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_population integer;
BEGIN
  SELECT COALESCE(SUM(bt.provides_population * b.level), 0) INTO v_total_population
  FROM public.buildings b
  JOIN public.building_types bt ON bt.building_type = b.building_type
  WHERE b.player_id = p_player_id
    AND bt.provides_population > 0;

  -- Update profiles table
  UPDATE public.profiles
  SET population = v_total_population
  WHERE id = p_player_id;

  RETURN v_total_population;
END;
$$;

COMMENT ON FUNCTION public.calculate_population(uuid) IS 'Calculate and update total population from buildings';

-- Update place_building to check population requirements
CREATE OR REPLACE FUNCTION public.place_building(
  p_building_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building_info record;
  v_cost integer;
  v_size_x integer;
  v_size_y integer;
  v_current_crystals bigint;
  v_current_population integer;
  v_building_id integer;
  v_check_x integer;
  v_check_y integer;
BEGIN
  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = p_building_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building type "%" does not exist', p_building_type;
  END IF;

  v_cost := v_building_info.base_cost_crystals;
  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Check population requirement
  SELECT COALESCE(population, 0) INTO v_current_population
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_population < v_building_info.population_required THEN
    RAISE EXCEPTION 'Insufficient population: required %, available %', 
      v_building_info.population_required, v_current_population;
  END IF;

  -- Check if player has enough crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
  END IF;

  -- Check if grid cells are available (for multi-cell buildings)
  FOR v_check_x IN p_grid_x..(p_grid_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_grid_y..(p_grid_y + v_size_y - 1) LOOP
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%%) is already occupied', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Place building (only record top-left corner for multi-cell buildings)
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, p_building_type, p_grid_x, p_grid_y, 1)
  RETURNING id INTO v_building_id;

  -- Update population if community building
  IF v_building_info.provides_population > 0 THEN
    PERFORM public.calculate_population(v_player_id);
  END IF;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'place_building', 1);

  RETURN v_building_id;
END;
$$;

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks population requirements.';

-- Update remove_building to recalculate population
CREATE OR REPLACE FUNCTION public.remove_building(p_building_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_info record;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  -- Remove building
  DELETE FROM public.buildings WHERE id = p_building_id;

  -- Recalculate population
  IF v_building_info.provides_population > 0 THEN
    PERFORM public.calculate_population(v_player_id);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_building(integer) IS 'Remove a building from the town grid and recalculate population.';

-- Function to get available buildings (filtered by population)
CREATE OR REPLACE FUNCTION public.get_available_buildings()
RETURNS TABLE (
  building_type text,
  name text,
  category text,
  base_cost_crystals integer,
  size_x integer,
  size_y integer,
  provides_population integer,
  population_required integer,
  max_level integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_population integer;
BEGIN
  -- Get player's current population
  SELECT COALESCE(population, 0) INTO v_current_population
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return buildings that player can afford (population-wise)
  RETURN QUERY
  SELECT 
    bt.building_type,
    bt.name,
    bt.category,
    bt.base_cost_crystals,
    bt.size_x,
    bt.size_y,
    bt.provides_population,
    bt.population_required,
    bt.max_level
  FROM public.building_types bt
  WHERE bt.population_required <= v_current_population
  ORDER BY bt.population_required, bt.name;
END;
$$;

COMMENT ON FUNCTION public.get_available_buildings() IS 'Get buildings available to the player based on population requirements';


-- Create town expansion system (expandable town grid)

-- Add town_size column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'town_size'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN town_size integer DEFAULT 10;
  END IF;
END $$;

-- Create town_expansions table to track expansion history
CREATE TABLE IF NOT EXISTS public.town_expansions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('north', 'south', 'east', 'west', 'all')),
  old_size integer NOT NULL,
  new_size integer NOT NULL,
  cost_crystals integer NOT NULL,
  expanded_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.town_expansions ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view own expansions
CREATE POLICY "Players can view own expansions" ON public.town_expansions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Policy: Players can insert own expansions
CREATE POLICY "Players can insert own expansions" ON public.town_expansions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.town_expansions;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_town_expansions_player ON public.town_expansions(player_id);

-- Function to expand town
CREATE OR REPLACE FUNCTION public.expand_town(
  p_direction text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_size integer;
  v_new_size integer;
  v_expansion_cost integer;
  v_current_crystals bigint;
  v_result jsonb;
BEGIN
  -- Validate direction
  IF p_direction NOT IN ('north', 'south', 'east', 'west', 'all') THEN
    RAISE EXCEPTION 'Invalid direction: %. Must be north, south, east, west, or all', p_direction;
  END IF;

  -- Get current town size
  SELECT COALESCE(town_size, 10) INTO v_current_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate new size and cost
  IF p_direction = 'all' THEN
    v_new_size := v_current_size + 5; -- Expand by 5x5
    v_expansion_cost := v_current_size * 1000; -- Cost scales with current size
  ELSE
    v_new_size := v_current_size + 2; -- Expand by 2 in one direction
    v_expansion_cost := v_current_size * 500;
  END IF;

  -- Maximum size limit
  IF v_new_size > 30 THEN
    RAISE EXCEPTION 'Maximum town size (30x30) reached';
  END IF;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_expansion_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_expansion_cost, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_expansion_cost,
      town_size = v_new_size
  WHERE id = v_player_id;

  -- Record expansion
  INSERT INTO public.town_expansions (
    player_id,
    direction,
    old_size,
    new_size,
    cost_crystals
  )
  VALUES (
    v_player_id,
    p_direction,
    v_current_size,
    v_new_size,
    v_expansion_cost
  );

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'old_size', v_current_size,
    'new_size', v_new_size,
    'cost_crystals', v_expansion_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.expand_town(text) IS 'Expand town grid size. Direction: north, south, east, west, or all (default).';

-- Function to get expansion cost
CREATE OR REPLACE FUNCTION public.get_expansion_cost(
  p_direction text DEFAULT 'all'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_size integer;
  v_cost integer;
BEGIN
  -- Get current town size
  SELECT COALESCE(town_size, 10) INTO v_current_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate cost
  IF p_direction = 'all' THEN
    v_cost := v_current_size * 1000;
  ELSE
    v_cost := v_current_size * 500;
  END IF;

  RETURN v_cost;
END;
$$;

COMMENT ON FUNCTION public.get_expansion_cost(text) IS 'Get the cost to expand town in a given direction';


-- Create decorations system (purely cosmetic items)

-- Create decorations table
CREATE TABLE IF NOT EXISTS public.decorations (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  decoration_type text NOT NULL,
  grid_x integer NOT NULL CHECK (grid_x >= 0),
  grid_y integer NOT NULL CHECK (grid_y >= 0),
  placed_at timestamptz DEFAULT now(),
  UNIQUE(player_id, grid_x, grid_y) -- One decoration per grid cell
);

-- Create decoration_types table
CREATE TABLE IF NOT EXISTS public.decoration_types (
  decoration_type text PRIMARY KEY,
  name text NOT NULL,
  icon text NOT NULL,
  cost_crystals integer NOT NULL DEFAULT 50,
  size_x integer NOT NULL DEFAULT 1,
  size_y integer NOT NULL DEFAULT 1,
  category text NOT NULL CHECK (category IN ('statue', 'tree', 'fountain', 'other'))
);

-- Insert decoration types
INSERT INTO public.decoration_types (decoration_type, name, icon, cost_crystals, size_x, size_y, category) VALUES
  ('statue_warrior', 'Warrior Statue', '🗿', 200, 1, 1, 'statue'),
  ('statue_wizard', 'Wizard Statue', '🧙', 200, 1, 1, 'statue'),
  ('statue_dragon', 'Dragon Statue', '🐉', 500, 2, 2, 'statue'),
  ('tree_oak', 'Oak Tree', '🌳', 100, 1, 1, 'tree'),
  ('tree_pine', 'Pine Tree', '🌲', 100, 1, 1, 'tree'),
  ('tree_cherry', 'Cherry Blossom', '🌸', 150, 1, 1, 'tree'),
  ('tree_magic', 'Magic Tree', '✨', 300, 1, 1, 'tree'),
  ('fountain_small', 'Small Fountain', '⛲', 300, 1, 1, 'fountain'),
  ('fountain_grand', 'Grand Fountain', '🏛️', 1000, 2, 2, 'fountain'),
  ('bench', 'Park Bench', '🪑', 50, 1, 1, 'other'),
  ('lamp_post', 'Lamp Post', '🕯️', 75, 1, 1, 'other'),
  ('flower_bed', 'Flower Bed', '🌺', 80, 1, 1, 'other'),
  ('hedge', 'Hedge', '🌿', 60, 1, 1, 'other'),
  ('archway', 'Decorative Archway', '🚪', 400, 1, 2, 'other')
ON CONFLICT (decoration_type) DO NOTHING;

-- Enable RLS
ALTER TABLE public.decorations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decoration_types ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view decoration types
CREATE POLICY "Anyone can view decoration types" ON public.decoration_types
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view all decorations (for visiting towns)
CREATE POLICY "Anyone can view decorations" ON public.decorations
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can insert own decorations
CREATE POLICY "Players can insert own decorations" ON public.decorations
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Policy: Players can update own decorations
CREATE POLICY "Players can update own decorations" ON public.decorations
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Policy: Players can delete own decorations
CREATE POLICY "Players can delete own decorations" ON public.decorations
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.decorations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.decoration_types;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_decorations_player ON public.decorations(player_id);
CREATE INDEX IF NOT EXISTS idx_decorations_position ON public.decorations(grid_x, grid_y);

-- Function to place decoration
CREATE OR REPLACE FUNCTION public.place_decoration(
  p_decoration_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_decoration_info record;
  v_cost integer;
  v_size_x integer;
  v_size_y integer;
  v_current_crystals bigint;
  v_decoration_id integer;
  v_check_x integer;
  v_check_y integer;
  v_town_size integer;
BEGIN
  -- Get decoration type info
  SELECT * INTO v_decoration_info
  FROM public.decoration_types
  WHERE decoration_type = p_decoration_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Decoration type "%" does not exist', p_decoration_type;
  END IF;

  v_cost := v_decoration_info.cost_crystals;
  v_size_x := v_decoration_info.size_x;
  v_size_y := v_decoration_info.size_y;

  -- Get town size
  SELECT COALESCE(town_size, 10) INTO v_town_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check bounds
  IF p_grid_x + v_size_x > v_town_size OR p_grid_y + v_size_y > v_town_size THEN
    RAISE EXCEPTION 'Decoration would be placed outside town bounds';
  END IF;

  -- Check if player has enough crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
  END IF;

  -- Check if grid cells are available (for multi-cell decorations)
  FOR v_check_x IN p_grid_x..(p_grid_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_grid_y..(p_grid_y + v_size_y - 1) LOOP
      -- Check for buildings
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%%) is occupied by a building', v_check_x, v_check_y;
      END IF;
      
      -- Check for other decorations
      IF EXISTS (
        SELECT 1 FROM public.decorations
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%%) is already occupied by a decoration', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Place decoration (only record top-left corner for multi-cell decorations)
  INSERT INTO public.decorations (player_id, decoration_type, grid_x, grid_y)
  VALUES (v_player_id, p_decoration_type, p_grid_x, p_grid_y)
  RETURNING id INTO v_decoration_id;

  RETURN v_decoration_id;
END;
$$;

COMMENT ON FUNCTION public.place_decoration(text, integer, integer) IS 'Place a decoration on the town grid. Returns decoration ID.';

-- Function to remove decoration
CREATE OR REPLACE FUNCTION public.remove_decoration(p_decoration_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_decoration record;
BEGIN
  -- Get decoration
  SELECT * INTO v_decoration
  FROM public.decorations
  WHERE id = p_decoration_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Decoration % not found or does not belong to this player', p_decoration_id;
  END IF;

  -- Remove decoration (no refund - purely cosmetic)
  DELETE FROM public.decorations WHERE id = p_decoration_id;
END;
$$;

COMMENT ON FUNCTION public.remove_decoration(integer) IS 'Remove a decoration from the town grid (no refund).';


-- Create push notifications system

-- Create push_subscriptions table to store device tokens
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  device_info jsonb,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz DEFAULT now(),
  UNIQUE(player_id, endpoint)
);

-- Create notification_preferences table
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  player_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  crops_ready boolean DEFAULT true,
  factory_complete boolean DEFAULT true,
  orders_expiring boolean DEFAULT true,
  quest_available boolean DEFAULT true,
  friend_help boolean DEFAULT true,
  coven_task_complete boolean DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Policy: Players can manage own subscriptions
CREATE POLICY "Players can view own subscriptions" ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own subscriptions" ON public.push_subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own subscriptions" ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own subscriptions" ON public.push_subscriptions
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Policy: Players can manage own preferences
CREATE POLICY "Players can view own preferences" ON public.notification_preferences
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own preferences" ON public.notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own preferences" ON public.notification_preferences
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Function to register push subscription
CREATE OR REPLACE FUNCTION public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_device_info jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  INSERT INTO public.push_subscriptions (
    player_id,
    endpoint,
    p256dh,
    auth,
    device_info
  )
  VALUES (
    v_player_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    p_device_info
  )
  ON CONFLICT (player_id, endpoint) DO UPDATE SET
    p256dh = EXCLUDED.p256dh,
    auth = EXCLUDED.auth,
    device_info = EXCLUDED.device_info,
    last_used_at = now();

  -- Initialize preferences if not exists
  INSERT INTO public.notification_preferences (player_id)
  VALUES (v_player_id)
  ON CONFLICT (player_id) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.register_push_subscription(text, text, text, jsonb) IS 'Register a push notification subscription for the current user';

-- Function to update notification preferences
CREATE OR REPLACE FUNCTION public.update_notification_preferences(
  p_crops_ready boolean DEFAULT NULL,
  p_factory_complete boolean DEFAULT NULL,
  p_orders_expiring boolean DEFAULT NULL,
  p_quest_available boolean DEFAULT NULL,
  p_friend_help boolean DEFAULT NULL,
  p_coven_task_complete boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  INSERT INTO public.notification_preferences (player_id)
  VALUES (v_player_id)
  ON CONFLICT (player_id) DO NOTHING;

  UPDATE public.notification_preferences
  SET
    crops_ready = COALESCE(p_crops_ready, crops_ready),
    factory_complete = COALESCE(p_factory_complete, factory_complete),
    orders_expiring = COALESCE(p_orders_expiring, orders_expiring),
    quest_available = COALESCE(p_quest_available, quest_available),
    friend_help = COALESCE(p_friend_help, friend_help),
    coven_task_complete = COALESCE(p_coven_task_complete, coven_task_complete),
    updated_at = now()
  WHERE player_id = v_player_id;
END;
$$;

COMMENT ON FUNCTION public.update_notification_preferences(boolean, boolean, boolean, boolean, boolean, boolean) IS 'Update notification preferences for the current user';

-- Function to get subscriptions for a player (for server-side notification sending)
CREATE OR REPLACE FUNCTION public.get_player_subscriptions(p_player_id uuid)
RETURNS TABLE (
  endpoint text,
  p256dh text,
  auth text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT ps.endpoint, ps.p256dh, ps.auth
  FROM public.push_subscriptions ps
  JOIN public.notification_preferences np ON np.player_id = ps.player_id
  WHERE ps.player_id = p_player_id
    AND ps.last_used_at > now() - interval '30 days'; -- Only active subscriptions
END;
$$;

COMMENT ON FUNCTION public.get_player_subscriptions(uuid) IS 'Get active push subscriptions for a player (server-side use)';


-- Create Aether (premium currency) system

-- Add aether column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'aether'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN aether integer DEFAULT 0;
  END IF;
END $$;

-- Create premium_shop table
CREATE TABLE IF NOT EXISTS public.premium_shop (
  id serial PRIMARY KEY,
  item_type text NOT NULL CHECK (item_type IN ('speed_up', 'decoration', 'building', 'boost', 'bundle')),
  item_id text NOT NULL,
  name text NOT NULL,
  description text,
  icon text,
  cost_aether integer NOT NULL,
  cost_crystals integer DEFAULT 0, -- Some items can be bought with crystals too
  available boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  metadata jsonb -- Additional data (e.g., speed_up_minutes, building_type, etc.)
);

-- Insert premium shop items
INSERT INTO public.premium_shop (item_type, item_id, name, description, icon, cost_aether, cost_crystals, sort_order, metadata) VALUES
  -- Speed-ups
  ('speed_up', 'speed_1h', '1 Hour Speed-Up', 'Instantly complete 1 hour of production', '⏩', 10, 0, 1, '{"minutes": 60}'),
  ('speed_up', 'speed_3h', '3 Hour Speed-Up', 'Instantly complete 3 hours of production', '⏩⏩', 25, 0, 2, '{"minutes": 180}'),
  ('speed_up', 'speed_8h', '8 Hour Speed-Up', 'Instantly complete 8 hours of production', '⏩⏩⏩', 60, 0, 3, '{"minutes": 480}'),
  
  -- Premium Decorations
  ('decoration', 'statue_golden', 'Golden Statue', 'Exclusive golden statue decoration', '🏆', 50, 0, 10, '{"decoration_type": "statue_golden"}'),
  ('decoration', 'fountain_magic', 'Magic Fountain', 'Enchanted fountain with magical effects', '✨', 75, 0, 11, '{"decoration_type": "fountain_magic"}'),
  
  -- Premium Buildings
  ('building', 'factory_premium', 'Premium Factory', 'Upgraded factory with faster production', '🏭', 100, 0, 20, '{"building_type": "premium_factory", "production_speed": 1.5}'),
  
  -- Boosts
  ('boost', 'xp_boost_24h', '24h XP Boost', 'Double XP for 24 hours', '📈', 30, 0, 30, '{"duration_hours": 24, "xp_multiplier": 2.0}'),
  ('boost', 'crystal_boost_24h', '24h Crystal Boost', '50% more crystals from all sources', '💎', 40, 0, 31, '{"duration_hours": 24, "crystal_multiplier": 1.5}'),
  
  -- Bundles
  ('bundle', 'starter_pack', 'Starter Pack', 'Great value starter bundle', '🎁', 100, 0, 100, '{"items": [{"type": "crystals", "amount": 1000}, {"type": "speed_up", "minutes": 120}]}')
ON CONFLICT DO NOTHING;

-- Create aether_transactions table
CREATE TABLE IF NOT EXISTS public.aether_transactions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  transaction_type text NOT NULL CHECK (transaction_type IN ('purchase', 'reward', 'spent', 'refund')),
  amount integer NOT NULL,
  description text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.premium_shop ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.aether_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view premium shop
CREATE POLICY "Anyone can view premium shop" ON public.premium_shop
  FOR SELECT TO authenticated
  USING (available = true);

-- Policy: Players can view own transactions
CREATE POLICY "Players can view own transactions" ON public.aether_transactions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Policy: System can insert transactions
CREATE POLICY "System can insert transactions" ON public.aether_transactions
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_aether_transactions_player ON public.aether_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_aether_transactions_type ON public.aether_transactions(transaction_type);

-- Function to purchase premium shop item
CREATE OR REPLACE FUNCTION public.purchase_premium_item(
  p_item_id text,
  p_use_aether boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_item record;
  v_current_aether integer;
  v_current_crystals bigint;
  v_cost integer;
  v_result jsonb;
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
    WHERE id = v_player_id;

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
    WHERE id = v_player_id;
  END IF;

  -- Apply item effects based on type
  CASE v_item.item_type
    WHEN 'speed_up' THEN
      -- Speed-up logic would be handled by client or separate RPC
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'speed_up',
        'minutes', (v_item.metadata->>'minutes')::integer
      );
    WHEN 'decoration' THEN
      -- Decoration would be added to inventory or placed directly
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'decoration',
        'decoration_type', v_item.metadata->>'decoration_type'
      );
    WHEN 'building' THEN
      -- Building would be unlocked or placed
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'building',
        'building_type', v_item.metadata->>'building_type'
      );
    WHEN 'boost' THEN
      -- Boost would be activated
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'boost',
        'duration_hours', (v_item.metadata->>'duration_hours')::integer,
        'metadata', v_item.metadata
      );
    WHEN 'bundle' THEN
      -- Bundle items would be awarded
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'bundle',
        'items', v_item.metadata->'items'
      );
    ELSE
      v_result := jsonb_build_object('success', true);
  END CASE;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_premium_item(text, boolean) IS 'Purchase an item from the premium shop using aether or crystals';

-- Function to award aether (for admin/rewards)
CREATE OR REPLACE FUNCTION public.award_aether(
  p_player_id uuid,
  p_amount integer,
  p_description text DEFAULT 'Awarded aether'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Award aether
  UPDATE public.profiles
  SET aether = COALESCE(aether, 0) + p_amount
  WHERE id = p_player_id;

  -- Record transaction
  INSERT INTO public.aether_transactions (player_id, transaction_type, amount, description)
  VALUES (p_player_id, 'reward', p_amount, p_description);
END;
$$;

COMMENT ON FUNCTION public.award_aether(uuid, integer, text) IS 'Award aether to a player (admin/system use)';


-- Implement speed-up system for factory production

-- Create speed_ups table to track active speed-ups
CREATE TABLE IF NOT EXISTS public.speed_ups (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  speed_up_type text NOT NULL CHECK (speed_up_type IN ('factory', 'crop', 'global')),
  target_id integer, -- factory_id, plot_id, or NULL for global
  minutes integer NOT NULL,
  used_at timestamptz DEFAULT now(),
  expires_at timestamptz
);

-- Enable RLS
ALTER TABLE public.speed_ups ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view own speed-ups
CREATE POLICY "Players can view own speed-ups" ON public.speed_ups
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own speed-ups" ON public.speed_ups
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own speed-ups" ON public.speed_ups
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.speed_ups;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_speed_ups_player ON public.speed_ups(player_id);
CREATE INDEX IF NOT EXISTS idx_speed_ups_expires ON public.speed_ups(expires_at) WHERE expires_at IS NOT NULL;

-- Function to apply speed-up to factory production
CREATE OR REPLACE FUNCTION public.apply_factory_speed_up(
  p_factory_type text,
  p_slot integer,
  p_minutes integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_queue_item record;
BEGIN
  -- Get queue item
  SELECT * INTO v_queue_item
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Production slot not found';
  END IF;

  -- Apply speed-up (reduce finish time)
  UPDATE public.factory_queue
  SET finishes_at = GREATEST(finishes_at - (p_minutes || ' minutes')::interval, now())
  WHERE player_id = v_player_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  -- Record speed-up usage
  INSERT INTO public.speed_ups (player_id, speed_up_type, target_id, minutes)
  VALUES (v_player_id, 'factory', p_slot, p_minutes);
END;
$$;

COMMENT ON FUNCTION public.apply_factory_speed_up(text, integer, integer) IS 'Apply speed-up to factory production slot';

-- Function to apply speed-up to crop growth
CREATE OR REPLACE FUNCTION public.apply_crop_speed_up(
  p_plot_index integer,
  p_minutes integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_plot record;
BEGIN
  -- Get plot
  SELECT * INTO v_plot
  FROM public.farm_plots
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plot % not found', p_plot_index;
  END IF;

  IF v_plot.crop_id IS NULL THEN
    RAISE EXCEPTION 'Plot % has no crop planted', p_plot_index;
  END IF;

  -- Apply speed-up (reduce ready time)
  UPDATE public.farm_plots
  SET ready_at = GREATEST(ready_at - (p_minutes || ' minutes')::interval, now())
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index;

  -- Record speed-up usage
  INSERT INTO public.speed_ups (player_id, speed_up_type, target_id, minutes)
  VALUES (v_player_id, 'crop', p_plot_index, p_minutes);
END;
$$;

COMMENT ON FUNCTION public.apply_crop_speed_up(integer, integer) IS 'Apply speed-up to crop growth';

-- Update purchase_premium_item to handle speed-ups
CREATE OR REPLACE FUNCTION public.purchase_premium_item(
  p_item_id text,
  p_use_aether boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_item record;
  v_current_aether integer;
  v_current_crystals bigint;
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
    WHERE id = v_player_id;

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
    WHERE id = v_player_id;
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
      
      -- Add to player's speed-up inventory (could be a separate table, but for now we'll track usage)
      
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
      -- Create active boost record
      INSERT INTO public.active_boosts (player_id, boost_type, multiplier, expires_at)
      VALUES (
        v_player_id,
        CASE 
          WHEN v_item.item_id LIKE '%xp%' THEN 'xp'
          WHEN v_item.item_id LIKE '%crystal%' THEN 'crystal'
          ELSE 'general'
        END,
        COALESCE((v_item.metadata->>'xp_multiplier')::numeric, (v_item.metadata->>'crystal_multiplier')::numeric, 1.0),
        now() + ((v_item.metadata->>'duration_hours')::integer || ' hours')::interval
      )
      ON CONFLICT (player_id, boost_type) DO UPDATE SET
        multiplier = EXCLUDED.multiplier,
        expires_at = EXCLUDED.expires_at;
      
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'boost',
        'duration_hours', (v_item.metadata->>'duration_hours')::integer,
        'metadata', v_item.metadata,
        'message', 'Boost activated!'
      );
      
    WHEN 'bundle' THEN
      -- Award bundle items
      -- This would need to parse the bundle items and award them
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'bundle',
        'items', v_item.metadata->'items',
        'message', 'Bundle items added to your inventory!'
      );
    ELSE
      v_result := jsonb_build_object('success', true);
  END CASE;

  RETURN v_result;
END;
$$;

-- Create active_boosts table for temporary boosts
CREATE TABLE IF NOT EXISTS public.active_boosts (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  boost_type text NOT NULL CHECK (boost_type IN ('xp', 'crystal', 'production', 'general')),
  multiplier numeric NOT NULL DEFAULT 1.0,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (player_id, boost_type)
);

-- Enable RLS
ALTER TABLE public.active_boosts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Players can view own boosts" ON public.active_boosts
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.active_boosts;

-- Create index
CREATE INDEX IF NOT EXISTS idx_active_boosts_expires ON public.active_boosts(expires_at);

-- Function to get active boost multiplier
CREATE OR REPLACE FUNCTION public.get_active_boost_multiplier(p_boost_type text)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_multiplier numeric := 1.0;
BEGIN
  SELECT multiplier INTO v_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = p_boost_type
    AND expires_at > now()
  LIMIT 1;

  RETURN COALESCE(v_multiplier, 1.0);
END;
$$;

COMMENT ON FUNCTION public.get_active_boost_multiplier(text) IS 'Get active boost multiplier for a boost type';


-- Integrate boost multipliers into reward systems

-- Update collect_factory to apply crystal boost multiplier
CREATE OR REPLACE FUNCTION public.collect_factory(p_slot integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory_type text;
  v_queue record;
  v_output jsonb;
  v_key text;
  v_qty_str text;
  v_qty integer;
  v_item_id integer;
  v_new_crystals bigint;
  v_crystal_multiplier numeric := 1.0;
BEGIN
  -- Fetch queue entry
  SELECT * INTO v_queue
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No production found in slot %', p_slot;
  END IF;

  v_factory_type := v_queue.factory_type;

  IF v_queue.finishes_at > now() THEN
    RAISE EXCEPTION 'Production in slot % not ready yet (finishes at %)', p_slot, v_queue.finishes_at;
  END IF;

  -- Get active crystal boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_crystal_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'crystal'
    AND expires_at > now()
  LIMIT 1;

  -- Get recipe output
  SELECT output INTO v_output
  FROM public.recipes
  WHERE id = v_queue.recipe_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe with id % not found', v_queue.recipe_id;
  END IF;

  -- Award output resources to inventory
  FOR v_key, v_qty_str IN SELECT key, value FROM jsonb_each_text(v_output) LOOP
    v_qty := v_qty_str::integer;

    -- Map output resource name to item_id
    CASE v_key
      WHEN 'crystals' THEN
        -- Apply crystal boost and add to profile crystals
        v_qty := (v_qty * v_crystal_multiplier)::integer;
        UPDATE public.profiles
        SET crystals = crystals + v_qty
        WHERE id = v_player_id;
      ELSE
        -- Other items go to inventory
        CASE v_key
          WHEN 'wheat' THEN v_item_id := 1;
          WHEN 'bread' THEN v_item_id := 2;
          WHEN 'carrot' THEN v_item_id := 2;
          WHEN 'potato' THEN v_item_id := 3;
          WHEN 'tomato' THEN v_item_id := 4;
          WHEN 'corn' THEN v_item_id := 5;
          WHEN 'pumpkin' THEN v_item_id := 6;
          WHEN 'berry' THEN v_item_id := 7;
          WHEN 'herbs' THEN v_item_id := 8;
          WHEN 'magic_mushroom' THEN v_item_id := 9;
          WHEN 'enchanted_flower' THEN v_item_id := 10;
          ELSE NULL;
        END CASE;

        IF v_item_id IS NOT NULL THEN
          INSERT INTO public.inventory (player_id, item_id, quantity)
          VALUES (v_player_id, v_item_id, v_qty::bigint)
          ON CONFLICT (player_id, item_id) DO UPDATE SET
            quantity = inventory.quantity + excluded.quantity;
        END IF;
    END CASE;
  END LOOP;

  -- Remove queue entry
  DELETE FROM public.factory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  -- Return updated crystals quantity
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'produce', 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  RETURN v_new_crystals;
END;
$$;

-- Update fulfill_skyport_order to apply crystal boost
CREATE OR REPLACE FUNCTION public.fulfill_skyport_order(p_order_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_rewards jsonb;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
  v_key text;
  v_value text;
  v_result jsonb;
  v_crystal_multiplier numeric := 1.0;
  v_xp_multiplier numeric := 1.0;
BEGIN
  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % not found or does not belong to this player', p_order_id;
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order % has already been completed', p_order_id;
  END IF;

  IF v_order.expires_at < now() THEN
    RAISE EXCEPTION 'Order % has expired', p_order_id;
  END IF;

  -- Get active boost multipliers
  SELECT COALESCE(multiplier, 1.0) INTO v_crystal_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'crystal'
    AND expires_at > now()
  LIMIT 1;

  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;

  v_requirements := v_order.requirements;
  v_rewards := v_order.rewards;

  -- Check and deduct required items
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
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

  -- Award rewards (with boost multipliers)
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + ((v_rewards->>'crystals')::integer * v_crystal_multiplier)::bigint,
        xp = xp + COALESCE(((v_rewards->>'xp')::integer * v_xp_multiplier)::bigint, 0)
    WHERE id = v_player_id;
  END IF;

  -- Items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_required_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_required_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark order as completed
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Update quest progress for fulfilling orders
  PERFORM public.update_quest_progress(NULL, 'fulfill_order', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE(((v_rewards->>'crystals')::integer * v_crystal_multiplier)::integer, 0),
    'xp_awarded', COALESCE(((v_rewards->>'xp')::integer * v_xp_multiplier)::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Update check_achievements to apply XP boost
CREATE OR REPLACE FUNCTION public.check_achievements(
  p_condition_type text,
  p_increment_value integer DEFAULT 1,
  p_specific_value text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  r_achievement record;
  v_current_progress integer;
  v_new_progress integer;
  v_completed_achievements_count integer;
  v_player_level integer;
  v_player_crystals bigint;
  v_daily_streak integer;
  v_distinct_items_harvested integer;
  v_distinct_ores_mined integer;
  v_distinct_recipes_unlocked integer;
  v_distinct_animals_acquired integer;
  v_xp_multiplier numeric := 1.0;
BEGIN
  -- Get active XP boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;

  -- Fetch player profile data for relevant conditions
  SELECT level, crystals, daily_streak INTO v_player_level, v_player_crystals, v_daily_streak
  FROM public.profiles
  WHERE id = v_player_id;

  -- Iterate through all achievements matching the condition type
  FOR r_achievement IN
    SELECT a.id, a.name, a.description, a.category, a.condition_type, a.condition_value,
           a.reward_crystals, a.reward_xp, a.reward_title, a.icon,
           pa.progress, pa.completed_at, pa.claimed_at
    FROM public.achievements a
    LEFT JOIN public.player_achievements pa ON a.id = pa.achievement_id AND pa.player_id = v_player_id
    WHERE a.condition_type = p_condition_type
  LOOP
    -- Skip if already completed and claimed
    IF r_achievement.completed_at IS NOT NULL AND r_achievement.claimed_at IS NOT NULL THEN
      CONTINUE;
    END IF;

    v_current_progress := COALESCE((r_achievement.progress->>'value')::integer, 0);
    v_new_progress := v_current_progress;

    -- Update progress based on condition type (same logic as before)
    IF r_achievement.condition_type = 'harvest_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'produce_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'build_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'mine_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'animal_product_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'breed_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'player_level' THEN
      v_new_progress := v_player_level;
    ELSIF r_achievement.condition_type = 'crystals_earned' THEN
      v_new_progress := v_player_crystals;
    ELSIF r_achievement.condition_type = 'daily_streak' THEN
      v_new_progress := v_daily_streak;
    ELSIF r_achievement.condition_type = 'upgrade_level' THEN
      v_new_progress := GREATEST(v_current_progress, p_increment_value);
    ELSIF r_achievement.condition_type = 'crop_variety' THEN
      SELECT COUNT(DISTINCT i.item_id) INTO v_distinct_items_harvested
      FROM public.inventory i
      JOIN public.crops c ON i.item_id = c.item_id
      WHERE i.player_id = v_player_id;
      v_new_progress := v_distinct_items_harvested;
    ELSIF r_achievement.condition_type = 'ore_variety' THEN
      SELECT COUNT(DISTINCT i.item_id) INTO v_distinct_ores_mined
      FROM public.inventory i
      JOIN public.ore_types ot ON i.item_id = ot.item_id
      WHERE i.player_id = v_player_id;
      v_new_progress := v_distinct_ores_mined;
    ELSIF r_achievement.condition_type = 'recipe_variety' THEN
      SELECT COUNT(DISTINCT fq.recipe_id) INTO v_distinct_recipes_unlocked
      FROM public.factory_queue fq
      WHERE fq.player_id = v_player_id;
      v_new_progress := v_distinct_recipes_unlocked;
    ELSIF r_achievement.condition_type = 'animal_count' THEN
      SELECT COUNT(DISTINCT animal_type_id) INTO v_distinct_animals_acquired
      FROM public.zoo_enclosures
      WHERE player_id = v_player_id;
      v_new_progress := v_distinct_animals_acquired;
    ELSE
      CONTINUE;
    END IF;

    -- Update or insert player achievement progress
    INSERT INTO public.player_achievements (player_id, achievement_id, progress, completed_at)
    VALUES (v_player_id, r_achievement.id, jsonb_build_object('value', v_new_progress), NULL)
    ON CONFLICT (player_id, achievement_id) DO UPDATE SET
      progress = jsonb_build_object('value', EXCLUDED.progress->>'value'),
      completed_at = CASE
                       WHEN r_achievement.completed_at IS NULL AND EXCLUDED.progress->>'value' >= r_achievement.condition_value::text THEN NOW()
                       ELSE r_achievement.completed_at
                     END;

    -- Check if achievement is newly completed
    IF r_achievement.completed_at IS NULL AND v_new_progress >= r_achievement.condition_value THEN
      -- Award rewards immediately (with boost multipliers)
      UPDATE public.profiles
      SET crystals = crystals + r_achievement.reward_crystals,
          xp = xp + (r_achievement.reward_xp * v_xp_multiplier)::bigint
      WHERE id = v_player_id;

      RAISE NOTICE 'Achievement "%" completed by player %!', r_achievement.name, v_player_id;
    END IF;
  END LOOP;
END;
$$;

