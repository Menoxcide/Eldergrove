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