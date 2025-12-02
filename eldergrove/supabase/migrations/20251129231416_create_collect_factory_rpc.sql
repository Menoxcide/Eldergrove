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