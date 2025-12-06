-- Add SET search_path security setting to functions created after initial migration
-- This prevents search_path manipulation attacks by ensuring functions use a fixed search_path
-- All functions already use fully qualified names (e.g., public.table_name), so this is safe

-- Road system functions (from 20251209000001_add_roads_system.sql)
ALTER FUNCTION public.determine_road_type(UUID, INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.place_road(INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.update_adjacent_roads(UUID, INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.remove_road(INTEGER, INTEGER) SET search_path = '';

-- Zoo system functions
ALTER FUNCTION public.delete_enclosure(INTEGER) SET search_path = '';
ALTER FUNCTION public.remove_animal_from_enclosure(INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.add_animal_to_enclosure(INTEGER, INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.create_enclosure(TEXT) SET search_path = '';
ALTER FUNCTION public.collect_animal_production(INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.start_breeding(INTEGER) SET search_path = '';

-- Building and factory functions
ALTER FUNCTION public.get_energy_regeneration_rate(UUID) SET search_path = '';
ALTER FUNCTION public.get_factory_slot_info() SET search_path = '';
ALTER FUNCTION public.get_building_bonuses(UUID) SET search_path = '';
ALTER FUNCTION public.get_factory_slots_from_buildings(UUID, TEXT) SET search_path = '';
ALTER FUNCTION public.get_storage_capacity(INTEGER) SET search_path = '';
ALTER FUNCTION public.get_storage_usage(UUID) SET search_path = '';
ALTER FUNCTION public.get_player_storage_capacity(UUID) SET search_path = '';
ALTER FUNCTION public.get_current_energy(UUID) SET search_path = '';
ALTER FUNCTION public.get_max_energy(UUID) SET search_path = '';
ALTER FUNCTION public.get_production_speed_multiplier(UUID) SET search_path = '';
ALTER FUNCTION public.get_level_discount(UUID) SET search_path = '';
ALTER FUNCTION public.get_available_buildings() SET search_path = '';
ALTER FUNCTION public.place_building(TEXT, INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.upgrade_building(INTEGER) SET search_path = '';
ALTER FUNCTION public.place_decoration(TEXT, INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.get_xp_for_next_level(UUID) SET search_path = '';
ALTER FUNCTION public.check_and_level_up(UUID) SET search_path = '';
ALTER FUNCTION public.grant_xp(UUID, INTEGER) SET search_path = '';
ALTER FUNCTION public.upgrade_warehouse() SET search_path = '';
ALTER FUNCTION public.start_factory_production(TEXT, TEXT) SET search_path = '';
ALTER FUNCTION public.get_factory_slot_cost(INTEGER) SET search_path = '';
ALTER FUNCTION public.contribute_to_task(INTEGER, TEXT, INTEGER) SET search_path = '';
ALTER FUNCTION public.submit_regatta_task(INTEGER, INTEGER) SET search_path = '';
ALTER FUNCTION public.claim_daily_reward() SET search_path = '';

