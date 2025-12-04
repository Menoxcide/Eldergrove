-- Fix crop item_ids that appear to have been incorrectly set to seed/ore item_ids
-- Crops should use item_ids 1-10, not 100+ (seeds) or 20+ (ores)

UPDATE public.crops SET item_id = 1 WHERE name = 'Wheat';
UPDATE public.crops SET item_id = 2 WHERE name = 'Carrot';
UPDATE public.crops SET item_id = 3 WHERE name = 'Potato';
UPDATE public.crops SET item_id = 4 WHERE name = 'Tomato';
UPDATE public.crops SET item_id = 5 WHERE name = 'Corn';
UPDATE public.crops SET item_id = 6 WHERE name = 'Pumpkin';
UPDATE public.crops SET item_id = 7 WHERE name = 'Berry';
UPDATE public.crops SET item_id = 8 WHERE name = 'Herbs';
UPDATE public.crops SET item_id = 9 WHERE name = 'Magic Mushroom';
UPDATE public.crops SET item_id = 10 WHERE name = 'Enchanted Flower';