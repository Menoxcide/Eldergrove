-- Add building bonuses system
-- Buildings provide bonuses that stack (with diminishing returns)

-- Add bonus columns to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS bonus_type TEXT,
ADD COLUMN IF NOT EXISTS bonus_value NUMERIC DEFAULT 0;

-- Set bonuses for community buildings
-- Schools: XP gain multiplier (1% per school, max 10%)
-- Hospitals: Energy regeneration bonus (5 energy per hour per hospital, max 20)
-- Cinemas: Crystal generation bonus (1% per cinema, max 5%)
UPDATE public.building_types
SET bonus_type = CASE
  WHEN building_type = 'school' THEN 'xp_multiplier'
  WHEN building_type = 'hospital' THEN 'energy_regen'
  WHEN building_type = 'cinema' THEN 'crystal_generation'
  ELSE NULL
END,
bonus_value = CASE
  WHEN building_type = 'school' THEN 0.01  -- 1% XP multiplier per school
  WHEN building_type = 'hospital' THEN 5  -- 5 energy per hour per hospital
  WHEN building_type = 'cinema' THEN 0.01 -- 1% crystal generation per cinema
  ELSE 0
END
WHERE bonus_type IS NULL;

-- Factory buildings provide production slots (handled separately)
-- Each factory building on the map provides 2 base production slots

-- Function to calculate total bonuses from all buildings
CREATE OR REPLACE FUNCTION public.get_building_bonuses(p_player_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_bonuses JSONB := '{}'::JSONB;
  v_xp_multiplier NUMERIC := 0;
  v_energy_regen NUMERIC := 0;
  v_crystal_generation NUMERIC := 0;
  v_school_count INTEGER;
  v_hospital_count INTEGER;
  v_cinema_count INTEGER;
BEGIN
  -- Count buildings by type
  SELECT COUNT(*) INTO v_school_count
  FROM public.buildings
  WHERE player_id = p_player_id AND building_type = 'school';

  SELECT COUNT(*) INTO v_hospital_count
  FROM public.buildings
  WHERE player_id = p_player_id AND building_type = 'hospital';

  SELECT COUNT(*) INTO v_cinema_count
  FROM public.buildings
  WHERE player_id = p_player_id AND building_type = 'cinema';

  -- Calculate XP multiplier (1% per school, max 10%)
  IF v_school_count > 0 THEN
    v_xp_multiplier := LEAST(v_school_count * 0.01, 0.10);
  END IF;

  -- Calculate energy regeneration (5 per hour per hospital, max 20)
  IF v_hospital_count > 0 THEN
    v_energy_regen := LEAST(v_hospital_count * 5, 20);
  END IF;

  -- Calculate crystal generation (1% per cinema, max 5%)
  IF v_cinema_count > 0 THEN
    v_crystal_generation := LEAST(v_cinema_count * 0.01, 0.05);
  END IF;

  -- Build result JSON
  v_bonuses := jsonb_build_object(
    'xp_multiplier', v_xp_multiplier,
    'energy_regen', v_energy_regen,
    'crystal_generation', v_crystal_generation,
    'school_count', v_school_count,
    'hospital_count', v_hospital_count,
    'cinema_count', v_cinema_count
  );

  RETURN v_bonuses;
END;
$$;

-- Function to get factory production slots from buildings
CREATE OR REPLACE FUNCTION public.get_factory_slots_from_buildings(p_player_id UUID, p_factory_type TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_building_count INTEGER;
  v_slots_per_building INTEGER := 2; -- Each building provides 2 base slots
  v_total_slots INTEGER;
BEGIN
  -- Count buildings of this factory type on the town map
  SELECT COUNT(*) INTO v_building_count
  FROM public.buildings
  WHERE player_id = p_player_id 
    AND building_type = p_factory_type;

  -- Each building provides 2 base production slots
  v_total_slots := v_building_count * v_slots_per_building;

  -- Minimum 2 slots even if no buildings (for backwards compatibility)
  RETURN GREATEST(v_total_slots, 2);
END;
$$;

COMMENT ON COLUMN public.building_types.bonus_type IS 'Type of bonus this building provides: xp_multiplier, energy_regen, crystal_generation';
COMMENT ON COLUMN public.building_types.bonus_value IS 'Base bonus value per building';
COMMENT ON FUNCTION public.get_building_bonuses(UUID) IS 'Calculate total bonuses from all community buildings. Returns JSONB with xp_multiplier, energy_regen, crystal_generation, and counts.';
COMMENT ON FUNCTION public.get_factory_slots_from_buildings(UUID, TEXT) IS 'Get production slots from factory buildings on town map. Each building provides 2 slots.';

