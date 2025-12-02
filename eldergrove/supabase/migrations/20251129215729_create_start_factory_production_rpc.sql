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