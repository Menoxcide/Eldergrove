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