# How to Apply Supabase Migrations

## Option 1: Using Supabase CLI (Recommended)

1. **Install Supabase CLI** (if not already installed):
   ```bash
   npm install -g supabase
   ```

2. **Link to your project**:
   ```bash
   cd eldergrove
   supabase link --project-ref your-project-ref
   ```
   (Get your project ref from Supabase dashboard → Settings → General)

3. **Apply migrations**:
   ```bash
   supabase db push
   ```

## Option 2: Using Supabase Dashboard

1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy the contents of `supabase/migrations/20251202000024_fix_missing_tables_and_functions.sql`
4. Paste and run the SQL in the SQL Editor

## Option 3: Apply Individual Migrations

If you need to apply specific migrations, run them in order:

1. `20251202000012_add_population_requirements.sql` (creates get_available_buildings function)
2. `20251202000014_create_decorations_system.sql` (creates decorations tables)
3. `20251202000024_fix_missing_tables_and_functions.sql` (fix migration - ensures everything exists)

## Verify Migration Success

After applying migrations, verify in Supabase SQL Editor:

```sql
-- Check if tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('decorations', 'decoration_types');

-- Check if function exists
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'get_available_buildings';
```

Both queries should return results if migrations were successful.

