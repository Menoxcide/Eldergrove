-- Fix ad_watches table constraint to allow 'mining' production_type
ALTER TABLE public.ad_watches
DROP CONSTRAINT IF EXISTS ad_watches_production_type_check;

ALTER TABLE public.ad_watches
ADD CONSTRAINT ad_watches_production_type_check
CHECK (production_type IN ('farm', 'factory', 'zoo', 'mining'));

COMMENT ON COLUMN public.ad_watches.production_type IS 'Type of production: farm, factory, zoo, or mining';