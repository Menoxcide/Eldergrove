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