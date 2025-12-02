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