create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  crystals bigint default 500,
  level integer default 1,
  xp bigint default 0,
  created_at timestamptz default now()
);