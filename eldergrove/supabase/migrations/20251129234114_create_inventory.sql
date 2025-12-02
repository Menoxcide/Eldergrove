-- Create inventory table to track player items (wheat, bread, etc.)
CREATE TABLE IF NOT EXISTS public.inventory (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id integer NOT NULL,
  quantity bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (player_id, item_id)
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Create policies for owner-only access
CREATE POLICY "Users can view own inventory" ON public.inventory
  FOR SELECT TO authenticated
  USING ( auth.uid() = player_id );

CREATE POLICY "Users can insert own inventory" ON public.inventory
  FOR INSERT TO authenticated
  WITH CHECK ( auth.uid() = player_id );

CREATE POLICY "Users can update own inventory" ON public.inventory
  FOR UPDATE TO authenticated
  USING ( auth.uid() = player_id )
  WITH CHECK ( auth.uid() = player_id );

CREATE POLICY "Users can delete own inventory" ON public.inventory
  FOR DELETE TO authenticated
  USING ( auth.uid() = player_id );

-- Enable realtime subscriptions
ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory;