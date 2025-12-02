-- Create the farm_plots table for the farming system
create table public.farm_plots (
  player_id uuid not null references public.profiles(id) on delete cascade,
  plot_index integer not null,
  crop_id integer references public.crops(id),
  planted_at timestamptz,
  ready_at timestamptz,
  primary key (player_id, plot_index)
);