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