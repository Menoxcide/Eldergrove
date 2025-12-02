-- Create the recipes table for the factory system
create table public.recipes (
  id serial primary key,
  name text unique not null,
  input jsonb not null,
  output jsonb not null,
  minutes integer not null
);

-- Seed initial recipe
insert into public.recipes (name, input, output, minutes) values
('Bread', '{"Wheat": 3}', '{"crystals": 15}', 3);