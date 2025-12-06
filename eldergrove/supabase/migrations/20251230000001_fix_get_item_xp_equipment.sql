-- Fix get_item_xp to properly handle equipment items (30-39) in fallback case
-- Equipment items should have higher XP values even if not in marketplace

CREATE OR REPLACE FUNCTION public.get_item_xp(p_item_id integer, p_quantity integer DEFAULT 1)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base_xp integer;
  v_sell_price integer;
BEGIN
  -- Try to get sell price from marketplace to determine item value
  SELECT COALESCE(sell_price_crystals, 0) INTO v_sell_price
  FROM public.marketplace
  WHERE item_id = p_item_id;
  
  -- If not in marketplace, use default XP based on item_id ranges
  IF v_sell_price = 0 THEN
    -- Equipment items (30-39): High XP
    IF p_item_id >= 30 AND p_item_id <= 39 THEN
      v_base_xp := 50 + (p_item_id - 30) * 10; -- 50-140 XP per equipment item
    -- Ores (20-29): Higher XP
    ELSIF p_item_id >= 20 AND p_item_id <= 29 THEN
      v_base_xp := 15 + (p_item_id - 20) * 2; -- 15-33 XP per ore
    -- Crafted items (11-17): Medium-high XP
    ELSIF p_item_id >= 11 AND p_item_id <= 17 THEN
      v_base_xp := 10 + (p_item_id - 11) * 2; -- 10-22 XP per item
    -- Basic crops (1-10): Lower XP
    ELSE
      v_base_xp := 5 + (p_item_id - 1); -- 5-14 XP per crop
    END IF;
  ELSE
    -- Calculate XP based on sell price: 1 XP per 2 crystals value, minimum 5 XP
    v_base_xp := GREATEST(FLOOR(v_sell_price / 2.0), 5);
  END IF;
  
  RETURN v_base_xp * p_quantity;
END;
$$;

COMMENT ON FUNCTION public.get_item_xp(integer, integer) IS 'Calculate XP reward for an item based on its value. Returns XP amount for given quantity. Equipment items (30-39) have high XP values.';

