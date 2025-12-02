# MVP Step-by-Step Build Plan – Eldergrove (Township Clone)

Each task is atomic, testable, and can be completed in 15–90 minutes.  
Run tasks exactly in order. After each task, commit + test manually before moving to the next.

### Phase 0 – Project Setup (12 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 0.1 | `npx create-next-app@latest eldergrove --typescript --eslint --tailwind --app --src-dir --import-alias "@/*"` | Project boots with `npm run dev` |
| 0.2 | Delete everything inside `src/app` except `page.tsx`, `layout.tsx`, `globals.css` | Clean slate |
| 0.3 | Add `app/favicon.ico` and a placeholder `public/assets/logo.png` | Visible in browser tab |
| 0.4 | Install exact dependencies: `npm i zustand @supabase/supabase-js @supabase/auth-helpers-nextjs` | No errors |
| 0.5 | Install dev dependencies: `npm i -D @types/node @types/react @types/react-dom` | TypeScript happy |
| 0.6 | Create Supabase project (free tier) → copy URL and anon key | Keys ready |
| 0.7 | Create `.env.local` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` | No leaks (add to .gitignore) |
| 0.8 | Create `src/lib/supabase/client.ts` with `createClientComponentClient()` | Can import and use |
| 0.9 | Create `src/lib/supabase/server.ts` with `createServerComponentClient()` | Ready for later |
| 0.10 | Add `src/middleware.ts` that only allows `/` and `/login` for unauth users | Visiting any other route redirects to `/login` |
| 0.11 | Run `npx supabase init` inside project root | `supabase/` folder created |
| 0.12 | Add `src/app/(auth)/login/page.tsx` with simple "Login placeholder" text | Route works, protected routes redirect |

### Phase 1 – Authentication (8 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 1.1 | Enable Email/Password in Supabase Auth | Can register in dashboard |
| 1.2 | Create `src/components/auth/LoginForm.tsx` (email + password + submit) | Renders |
| 1.3 | Wire LoginForm to `supabase.auth.signInWithPassword` | Successful login sets session |
| 1.4 | Create `src/components/auth/RegisterForm.tsx` | Renders |
| 1.5 | Wire RegisterForm to `supabase.auth.signUp` | New user appears in Auth table |
| 1.6 | Create `src/app/(auth)/layout.tsx` that only contains `<html><body>{children}</body></html>` | Clean auth pages |
| 1.7 | Add logout button in `LoginForm` after success → redirects to `/login` | Session cleared |
| 1.8 | Create `src/components/layout/ProtectedLayout.tsx` that checks session and redirects to `/login` if none | Use in game layout later |

### Phase 2 – Player Profile & Global State (10 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 2.1 | Run `npx supabase gen types typescript --project-id <id> > src/types/supabase.ts` | Types file generated |
| 2.2 | Create table `profiles` via Supabase SQL Editor (id uuid PK, username text unique, crystals int8 default 500, level int default 1, xp int8 default 0, created_at timestamptz) | Table exists |
| 2.3 | Enable RLS on `profiles` + policy: `auth.uid() = id` for SELECT/UPDATE | Secure |
| 2.4 | Create edge function or RPC `create_profile_on_signup` trigger (after auth insert → insert into profiles) | New user auto-gets profile |
| 2.5 | Create `src/stores/usePlayerStore.ts` (Zustand) with fields: id, username, crystals, level, xp, loading | Store exists |
| 2.6 | Create `src/hooks/usePlayer.ts` that on mount fetches profile via supabase.from('profiles').select('*').single() and sets store | Data appears in React DevTools |
| 2.-rest| Add loading state + error handling in hook | Shows "Loading player…" |
| 2.8 | Create `src/components/game/ResourceBar.tsx` that reads from usePlayerStore and shows Crystals / Level / XP bar | Visible on screen |
| 2.9 | Add `src/app/(game)/layout.tsx` that wraps `<ProtectedLayout><ResourceBar />{children}</ProtectedLayout>` | Game shell appears after login |
| 2.10 | Redirect after successful login to `/game` | Works end-to-end |

### Phase 3 – Main Town Screen & Navigation (7 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 3.1 | Create `src/app/(game)/page.tsx` with placeholder "Welcome to Eldergrove" | Home screen |
| 3.2 | Create `src/components/layout/BottomNav.tsx` with 5 icons: Town | Farm | Factory | Coven | Profile | Active tab highlights |
| 3.3 | Add BottomNav to `(game)/layout.tsx` | Always visible on mobile |
| 3.4 | Create empty routes: `/farm`, `/factory`, `/coven`, `/profile` (all inside `(game)`) with simple text | Navigation works |
| 3.5 | Create `src/components/game/TownMap.tsx` – simple grid 10×10 with grass background | Renders |
| 3.6 | Replace `(game)/page.tsx` content with `<TownMap />` | Main view |
| 3.7 | Make TownMap clickable – clicking logs coordinates | Ready for building placement |

### Phase 4 – Crops & Farm MVP (12 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 4.1 | Create table `crops` (id serial PK, name text, grow_minutes int, yield_crystals int) | Seed with Wheat (2 min), Carrot (5 min) |
| 4.2 | Create table `farm_plots` (player_id uuid, plot_index int, crop_id int null, planted_at timestamptz null, ready_at timestamptz null) | 6 plots initially |
| 4.3 | Seed 6 plots for every new profile via trigger or migration | New users have empty plots |
| 4.4 | Enable RLS on both tables (owner only) | Secure |
| 4.5 | Create `src/stores/useFarmStore.ts` (plots array + setPlots) | Store ready |
| 4.6 | Create `src/app/(game)/farm/page.tsx` with "Farm Screen" | Route works |
| 4.7 | Create `src/components/game/CropField.tsx` that shows one plot (crop image or placeholder, timer) | Renders |
| 4.8 | In `useFarmStore` on mount: fetch all plots for player and set store | Plots load |
| 4.9 | Add realtime subscription to farm_plots in `useEffect` inside farm page | Changing in SQL Editor updates UI instantly |
| 4.10 | Implement "Plant Wheat" button on empty plot → calls RPC `plant_crop(plot_index, crop_id=1)` | Plot shows wheat + timer |
| 4.11 | Create client-side timer using `ready_at` and `setInterval` → auto-harvest when time reaches zero | Harvest button appears |
| 4.12 | Implement harvest → RPC `harvest_plot(plot_index)` → adds crystals to player and clears plot | Crystals increase in ResourceBar |

### Phase 5 – Basic Factory & Production (10 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 5.1 | Create tables: `recipes` (id, name, input JSONB, output JSONB, minutes int) | Example: Bread = 3 Wheat → 15 crystals, 3 min |
| 5.2 | Create `factories` (player_id, factory_type text, level int default 1) | Give every player 1 "Rune Bakery" on signup |
| 5.3 | Create `factory_queue` (player_id, factory_type, recipe_id, slot int, started_at, finishes_at) | Max 2 slots initially |
| 5.4 | RLS + realtime on factory_queue | Secure |
| 5.5 | Create `src/stores/useFactoryStore.ts` | Store ready |
| 5.6 | Create `/factory` page with list of player’s factories | Shows 1 bakery |
| 5.7 | Add "Start Bread" button → deducts wheat from inventory, inserts row into factory_queue | Queue appears |
| 5.8 | Show countdown timer per queue slot (client-side) | Works |
| 5.9 | Auto-complete when time reaches zero → RPC `collect_factory(slot)` → adds crystals | Crystals increase |
| 5.10 | Realtime updates when another device collects | Sync works |

### Phase 6 – Inventory System (5 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 6.1 | Create `inventory` table (player_id uuid, item_id int, quantity int8) | RLS owner only |
| 6.2 | Auto-create wheat x10 on new profile | Starting items |
| 6.3 | Create `useInventoryStore.ts` + realtime subscription | Inventory live |
| 6.4 | Show inventory bar somewhere (ResourceBar or separate tab) | See wheat count |
| 6.5 | Harvesting crops and collecting factory now correctly add/subtract from inventory | Full loop closed |

### Phase 7 – Offline Queue (Basic) (4 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 7.1 | Install `idb-keyval` | Offline storage |
| 7.2 | Create `src/hooks/useOfflineQueue.ts` – on failed supabase call, store action in IndexedDB | Queue grows when offline |
| 7.3 | Add network listener → when back online, replay queue in order | Actions eventually succeed |
| 7.4 | Test: turn off Wi-Fi → plant crop → turn on → crop appears | Offline works |

### Phase 8 – Polish & MVP Complete (6 tasks)

| # | Task | Success Criteria |
|---|------|------------------|
| 8.1 | Add loading skeletons everywhere | No flash of empty |
| 8.2 | Add toast notifications (use Sonner or react-hot-toast) | Success / error feedback |
| 8.3 | Add simple sound effects (plant, harvest, collect) using Howler.js or HTML5 audio | Feels alive |
| 8.4 | Make ResourceBar fixed top on mobile | Always visible |
| 8.5 | Add daily login crystals (500) via edge function + last_claimed column | Players come back |
| 8.6 | Play test full loop: register → plant → harvest → produce bread → collect crystals → repeat | Game is fun and complete |