-- Add equipment items (30-39) to marketplace for selling

-- Insert equipment items with sell prices
-- Prices are set based on rarity and crafting cost
INSERT INTO public.marketplace (item_id, sell_price_crystals, available) VALUES
(30, 50, true),   -- Iron Sword: 50 crystals per unit
(31, 100, true),  -- Steel Blade: 100 crystals per unit
(32, 200, true),  -- Diamond Armor: 200 crystals per unit
(33, 300, true),  -- Mithril Sword: 300 crystals per unit
(34, 500, true),  -- Aether Blade: 500 crystals per unit
(35, 750, true),  -- Dragon Scale Armor: 750 crystals per unit
(36, 1000, true)  -- Ancient Relic Weapon: 1000 crystals per unit
ON CONFLICT (item_id) DO UPDATE SET
  sell_price_crystals = EXCLUDED.sell_price_crystals,
  available = EXCLUDED.available;

COMMENT ON TABLE public.marketplace IS 'Marketplace prices for all sellable items including crops, production items, ores, and equipment';

