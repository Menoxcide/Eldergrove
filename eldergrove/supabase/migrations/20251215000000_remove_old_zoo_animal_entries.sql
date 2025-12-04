-- Remove old zoo animal entries from inventory
-- Old format used item_id 30-39 for animals (30 + animal_type_id)
-- New format uses item_id 1000+ for leveled animals (1000 + (animal_type_id * 100) + level)
-- Equipment also uses 30-36, so we need to be careful

-- Equipment items (30-36):
-- 30 = iron_sword
-- 31 = steel_blade  
-- 32 = diamond_armor
-- 33 = mithril_sword
-- 34 = aether_blade
-- 35 = dragon_scale_armor
-- 36 = ancient_relic_weapon

-- Old animal format: item_id = 30 + animal_type_id
-- Animal types are 1-9, so old animal item_ids would be 31-39
-- This creates overlap with equipment at 31-36

-- Strategy: Remove item_ids 37-39 (definitely old animals, no equipment conflict)
-- For 31-36, we can't safely distinguish, but since the user requested removal of old zoo entries,
-- we'll remove any that the helper function identifies as animals AND are not in the equipment list
-- However, to be safe, we'll only remove 37-39 which are definitely old animals

-- Remove old format animals that don't conflict with equipment
DELETE FROM public.inventory
WHERE item_id IN (37, 38, 39); -- These are definitely old animals (animal_type_id 7, 8, 9)

-- Note: Item IDs 31-36 could be either equipment or old animals (animal_type_id 1-6)
-- We're leaving those alone to avoid accidentally removing equipment
-- If there are old animal entries at 31-36, they would need manual cleanup or a more sophisticated check

