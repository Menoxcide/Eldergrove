-- Expand recipes table with new recipes using different plant combinations
-- Note: Recipe inputs/outputs use lowercase names that map to item_ids in RPCs

-- Update existing Bread recipe to use lowercase 'wheat' for consistency
UPDATE public.recipes
SET input = '{"wheat": 3}'::jsonb
WHERE name = 'Bread';

-- Add new recipes with varied plant combinations
INSERT INTO public.recipes (name, input, output, minutes) VALUES
('Vegetable Stew', '{"potato": 2, "tomato": 2, "carrot": 1}'::jsonb, '{"crystals": 50}'::jsonb, 5),
('Corn Bread', '{"corn": 2, "wheat": 2}'::jsonb, '{"crystals": 30}'::jsonb, 4),
('Pumpkin Pie', '{"pumpkin": 1, "wheat": 3}'::jsonb, '{"crystals": 60}'::jsonb, 6),
('Herbal Tea', '{"herbs": 2, "berry": 3}'::jsonb, '{"crystals": 25}'::jsonb, 3),
('Magic Potion', '{"magic_mushroom": 1, "enchanted_flower": 1}'::jsonb, '{"crystals": 100}'::jsonb, 10),
('Fruit Salad', '{"berry": 2, "tomato": 2}'::jsonb, '{"crystals": 35}'::jsonb, 4)
ON CONFLICT (name) DO NOTHING;

COMMENT ON TABLE public.recipes IS 'Factory recipes: input/output use lowercase item names that map to item_ids in RPC functions';

