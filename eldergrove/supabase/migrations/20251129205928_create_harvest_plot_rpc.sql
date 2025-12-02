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