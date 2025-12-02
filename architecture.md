# Full Architecture for a Township-Inspired Mobile Game Clone  
(Unique creative variations included: fantasy-themed world called **Eldergrove**, magic crystals instead of coins, rune-based factories, floating sky-islands, spirit animals, seasonal “Aether Events” instead of generic events, co-op “Coven” system, etc.)

### Tech Stack
| Layer              | Technology                                 | Why |
|--------------------|--------------------------------------------|--------------------------------------------|
| Frontend           | Next.js 15 (App Router) + React 19 + TypeScript | SSR/SSG for fast loading, great mobile PWA support |
| State Management   | Zustand + Zustand Middleware (persist, immer) | Lightweight, perfect for games, easy sync with Supabase |
| Backend / DB       | Supabase (PostgreSQL + Auth + Realtime + Storage) | Real-time out of the box, Row Level Security, free tier generous |
| Authentication     | Supabase Auth (email/password + Google + Apple) | Built-in, works perfectly with Next.js |
| Hosting            | Vercel (frontend) + Supabase (backend)     | Zero-config deployment |
| Mobile Wrapper     | Capacitor.js (turns Next.js into native iOS/Android app) | Best performance + access to native features |
| Analytics / Events | PostHog (self-hosted or cloud) or Mixpanel | Track in-game economy, retention, etc. |

### High-Level Architecture Diagram (text)

```
[Player Device (iOS/Android/PWA)]
        │
        ▼
Capacitor / WebView ←→ Next.js App (App Router)
        │                      │
        │                      ▼
        │               Zustand Global Stores
        │                      │
        │                      ▼
        │                Supabase Client
        │                ↙      ↘      ↘
        ▼               ▼        ▼       ▼
Auth Service    Realtime DB   Storage   Edge Functions
        │              │         │
        ▼              ▼         ▼
    PostgreSQL + RLS + Realtime broadcasts
```

### Complete Folder Structure

```
eldergrove/
├── app/                          # Next.js App Router
│   ├── (auth)/
│   │   ├── login/                page.tsx
│   │   └── register/             page.tsx
│   ├── (game)/                   # Protected game layout
│   │   ├── layout.tsx            # GameShell + loading Zustand
│   │   ├── page.tsx              # Main town screen (redirect here after login)
│   │   ├── farm/                 page.tsx
│   │   ├── factory/              page.tsx
│   │   ├── city/                 page.tsx
│   │   ├── mine/                 page.tsx
│   │   ├── zoo/                  page.tsx
│   │   ├── coven/                page.tsx   # Clan/Co-op
│   │   ├── events/               page.tsx
│   │   ├── skyport/              page.tsx   # Replaces train/airplane/ship
│   │   └── profile/              page.tsx
│   └── layout.tsx                # Root layout + providers
│   └── globals.css
│   └── favicon.ico
│
├── components/
│   ├── ui/                       # Shadcn/ui components
│   ├── game/
│   │   ├── TownMap.tsx               # Isometric or 2.5D town view
│   │   ├── BuildingCard.tsx
│   │   ├── ResourceBar.tsx
│   │   ├── CropField.tsx
│   │   ├── FactoryQueue.tsx
│   │   ├── MiniGameModal.tsx
│   │   └── notifications/
│   └── layout/
│       ├── Navbar.tsx
│       ├── BottomNav.tsx         # Mobile bottom navigation
│       └── GameLayout.tsx
│
├── lib/
│   ├── supabase/                 # Supabase client (browser + server)
│   │   ├── client.ts
│   │   └── server.ts
│   ├── services/
│   │   ├── playerService.ts      # All player RPCs
│   │   ├── farmService.ts
│   │   ├── factoryService.ts
│   │   ├── eventService.ts
│   │   └── covenService.ts
│   ├── utils/
│   │   ├── formatTime.ts
│   │   ├── calculateProduction.ts
│   │   └── aetherCalculations.ts  # Game economy formulas
│   └── constants/
│       ├── crops.ts
│       ├── buildings.ts
│       ├── animals.ts
│       └── events.ts
│
├── stores/                       # All Zustand stores
│   ├── usePlayerStore.ts         # Player level, crystals, XP, energy
│   ├── useFarmStore.ts
│   ├── useFactoryStore.ts
│   ├── useCityStore.ts
│   ├── useInventoryStore.ts
│   ├── useCovenStore.ts
│   └── useUIStore.ts             # Modals, toasts, sound toggle
│
├── hooks/
│   ├── useSupabaseRealtime.ts    # Custom hook for realtime subscriptions
│   ├── useProductionTimer.ts     # Factory & crop timers
│   └── useOfflineQueue.ts        # Queue actions when offline
│
├── public/
│   ├── assets/
│   │   ├── icons/
│   │   ├── buildings/
│   │   ├── crops/
│   │   └── sounds/
│   └── manifest.json
│
├── supabase/
│   ├── migrations/               # All SQL schema + RLS
│   ├── functions/                # Edge functions (e.g., daily reward, matchmaking)
│   └── seed.sql
│
├── types/
│   └── supabase.ts               # Generated types via supabase gen types
│
├── middleware.ts                # Protect /game routes
├── next.config.mjs
├── tsconfig.json
├── package.json
└── capacitor.config.ts
```

### Database Schema (Supabase PostgreSQL) – Key Tables

```sql
profiles            -- uuid, username, level, crystals, aether (premium), xp, energy
farm_plots          -- player_id, plot_id, crop_id, planted_at, ready_at
factories           -- player_id, factory_type, level, queue JSONB[]
factory_queue       -- Separate table for easier realtime
inventory           -- player_id, item_id, quantity
buildings           -- player_id, building_type, grid_x, grid_y, level
mine_digs           -- player_id, depth, last_dig_at, artifacts JSONB
zoo_enclosures      -- player_id, animal_id, name, bred_at
coven               -- id, name, emblem, leader_id
coven_members       -- coven_id, player_id, role, contribution
skyport_orders      -- player_id, order JSONB, completed_at
events_progress     -- player_id, event_id, stage, points
daily_rewards       -- player_id, last_claimed_date, streak
```

All tables have RLS policies: only owner or coven leader (for shared islands) can read/write.

### Where State Lives & How Data Flows

| Data Type               | Where it Lives                              | Sync Strategy |
|-------------------------|---------------------------------------------|-----------------------------|
| Player basics (level, crystals) | Zustand + Supabase `profiles` (realtime) | Realtime subscription on mount |
| Farm / Crops            | Zustand farmStore + `farm_plots`            | Realtime + local timers (useProductionTimer) |
| Factory queues          | Zustand + `factory_queue` table (realtime) | Realtime channel per player |
| Inventory               | Zustand inventoryStore                      | Realtime + optimistic updates |
| Buildings layout        | Zustand cityStore                           | Saved to DB only on "Save Layout" |
| Coven / Chat            | Supabase Realtime channel "coven:{id}"      | Pure realtime, no local cache |
| Events / Mini-games     | Local component state + backend progress    | Pull on open, push on complete |
| Offline actions         | useOfflineQueue → IndexedDB → flush on reconnect | Critical for mobile |

### Real-Time Implementation Example (useSupabaseRealtime.ts)

```ts
useEffect(() => {
  const channel = supabase
    .channel(`player:${playerId}`)
    .on('postgres_changes', 
        { event: '*', schema: 'public', table: 'factory_queue', filter: `player_id=eq.${playerId}` },
        (payload) => factoryStore.handleRealtime(payload)
    )
    .subscribe();

  return () => { supabase.removeChannel(channel); }
}, [playerId]);
```

### Services Layer Example (services/factoryService.ts)

```ts
export const startProduction = async (factoryId: number, recipeId: number) => {
  const { data, error } = await supabase.rpc('start_factory_production', {
    p_factory_id: factoryId,
    p_recipe_id: recipeId
  });
  if (error) throw error;
  // Optimistic UI already done in Zustand slice
  return data;
};
```

### Protected Routes & Auth Flow

`middleware.ts` redirects any `/game/*` to `/login` if no session.  
After login → `/game` → `layout.tsx` of `(game)` loads player data → hydrates all Zustand stores → shows TownMap.

### Offline Support Strategy

1. All actions go through service → if offline → queued in IndexedDB via `useOfflineQueue`.
2. When online again → flush queue in order.
3. Timers (crops, factories) continue running client-side using `last_updated_at` + server clock offset.

### Unique Creative Variations Already Baked In

- Currency: Magic Crystals + Aether Shards (premium)
- Theme: Fantasy sky-islands connected by portals
- Transportation: Skyport with “Aether Gliders” & “Spirit Whales”
- Co-op: Coven system with shared floating island & weekly “Leyline Regatta”
- Mini-games: Rune-match-3, Alchemy cooking, Spirit taming
- Season pass: “Aether Adventures” with Professor Verne’s Experiments

### Deployment Checklist

1. Vercel → connect repo → auto deploys
2. Supabase → run migrations → enable Realtime on all needed tables
3. Capacitor → `npx cap add ios/android` → build → open Xcode/Android Studio
4. Add app icons, splash screens, and sign for stores