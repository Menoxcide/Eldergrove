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