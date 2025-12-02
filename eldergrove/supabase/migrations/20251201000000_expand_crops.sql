-- Expand crops table with more crop types and add item_id mapping

-- Add item_id column to crops table to map to inventory items
ALTER TABLE public.crops ADD COLUMN IF NOT EXISTS item_id integer;

-- Update existing crops with item_id
UPDATE public.crops SET item_id = 1 WHERE name = 'Wheat';
UPDATE public.crops SET item_id = 2 WHERE name = 'Carrot';

-- Add new crops with varied growth times and yields
INSERT INTO public.crops (name, grow_minutes, yield_crystals, item_id) VALUES
('Potato', 3, 15, 3),
('Tomato', 4, 20, 4),
('Corn', 5, 25, 5),
('Pumpkin', 8, 40, 6),
('Berry', 2, 12, 11),
('Herbs', 3, 18, 12),
('Magic Mushroom', 10, 50, 13),
('Enchanted Flower', 12, 60, 14)
ON CONFLICT (name) DO NOTHING;

-- Make item_id NOT NULL after populating
ALTER TABLE public.crops ALTER COLUMN item_id SET NOT NULL;

-- Add comment
COMMENT ON COLUMN public.crops.item_id IS 'Maps to inventory item_id for harvested crops';

