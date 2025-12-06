-- Fix RLS policies that are flagged by Supabase linter for allowing anonymous access
-- Even though policies have TO authenticated, the linter requires explicit auth.uid() IS NOT NULL checks
-- This migration adds explicit authentication checks to satisfy the linter

-- achievements table
DROP POLICY IF EXISTS "Anyone can view achievements" ON public.achievements;
CREATE POLICY "Anyone can view achievements" ON public.achievements
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- active_boosts table
DROP POLICY IF EXISTS "Players can view own boosts" ON public.active_boosts;
CREATE POLICY "Players can view own boosts" ON public.active_boosts
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- ad_watches table (already fixed in previous migration, but ensuring consistency)
DROP POLICY IF EXISTS "Players can view their own ad watches" ON public.ad_watches;
CREATE POLICY "Players can view their own ad watches" ON public.ad_watches
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can insert their own ad watches" ON public.ad_watches;
CREATE POLICY "Players can insert their own ad watches" ON public.ad_watches
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- aether_transactions table
DROP POLICY IF EXISTS "Players can view own transactions" ON public.aether_transactions;
CREATE POLICY "Players can view own transactions" ON public.aether_transactions
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- animal_types table
DROP POLICY IF EXISTS "Anyone can view animal types" ON public.animal_types;
CREATE POLICY "Anyone can view animal types" ON public.animal_types
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- armories table
DROP POLICY IF EXISTS "Players can view own armories" ON public.armories;
CREATE POLICY "Players can view own armories" ON public.armories
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can update own armories" ON public.armories;
CREATE POLICY "Players can update own armories" ON public.armories
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id)
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own armories" ON public.armories;
CREATE POLICY "Players can delete own armories" ON public.armories
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- armory_queue table
DROP POLICY IF EXISTS "Players can view own armory queue" ON public.armory_queue;
CREATE POLICY "Players can view own armory queue" ON public.armory_queue
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can update own armory queue" ON public.armory_queue;
CREATE POLICY "Players can update own armory queue" ON public.armory_queue
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id)
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own armory queue" ON public.armory_queue;
CREATE POLICY "Players can delete own armory queue" ON public.armory_queue
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- armory_recipes table
DROP POLICY IF EXISTS "Anyone can view armory recipes" ON public.armory_recipes;
CREATE POLICY "Anyone can view armory recipes" ON public.armory_recipes
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- building_types table
DROP POLICY IF EXISTS "Anyone can view building types" ON public.building_types;
CREATE POLICY "Anyone can view building types" ON public.building_types
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- building_upgrade_costs table
DROP POLICY IF EXISTS "Anyone can view building upgrade costs" ON public.building_upgrade_costs;
CREATE POLICY "Anyone can view building upgrade costs" ON public.building_upgrade_costs
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- buildings table
DROP POLICY IF EXISTS "Players can view own buildings" ON public.buildings;
CREATE POLICY "Players can view own buildings" ON public.buildings
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can update own buildings" ON public.buildings;
CREATE POLICY "Players can update own buildings" ON public.buildings
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id)
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own buildings" ON public.buildings;
CREATE POLICY "Players can delete own buildings" ON public.buildings
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- coven table
DROP POLICY IF EXISTS "Enable conditional read access on coven" ON public.coven;
CREATE POLICY "Enable conditional read access on coven" ON public.coven
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven.id AND player_id = auth.uid()
    )
  ));

DROP POLICY IF EXISTS "Leaders can update own coven" ON public.coven;
CREATE POLICY "Leaders can update own coven" ON public.coven
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND leader_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND leader_id = auth.uid());

-- coven_activity_log table
DROP POLICY IF EXISTS "Members can view coven activity" ON public.coven_activity_log;
CREATE POLICY "Members can view coven activity" ON public.coven_activity_log
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_activity_log.coven_id AND player_id = auth.uid()
    )
  ));

-- coven_invitations table
DROP POLICY IF EXISTS "Leaders can view coven invitations" ON public.coven_invitations;
CREATE POLICY "Leaders can view coven invitations" ON public.coven_invitations
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_invitations.coven_id AND player_id = auth.uid() AND role = 'leader'
    )
  ));

DROP POLICY IF EXISTS "Users can view their invitations" ON public.coven_invitations;
CREATE POLICY "Users can view their invitations" ON public.coven_invitations
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND invitee_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their invitations" ON public.coven_invitations;
CREATE POLICY "Users can update their invitations" ON public.coven_invitations
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND invitee_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND invitee_id = auth.uid());

-- coven_members table
DROP POLICY IF EXISTS "Members can view coven members" ON public.coven_members;
CREATE POLICY "Members can view coven members" ON public.coven_members
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members cm2
      WHERE cm2.coven_id = coven_members.coven_id AND cm2.player_id = auth.uid()
    )
  ));

DROP POLICY IF EXISTS "Members can update their last_active" ON public.coven_members;
CREATE POLICY "Members can update their last_active" ON public.coven_members
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Leaders can manage coven members" ON public.coven_members;
CREATE POLICY "Leaders can manage coven members" ON public.coven_members
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members cm2
      WHERE cm2.coven_id = coven_members.coven_id AND cm2.player_id = auth.uid() AND cm2.role = 'leader'
    )
  ));

DROP POLICY IF EXISTS "Leaders can kick coven members" ON public.coven_members;
CREATE POLICY "Leaders can kick coven members" ON public.coven_members
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members cm2
      WHERE cm2.coven_id = coven_members.coven_id AND cm2.player_id = auth.uid() AND cm2.role = 'leader'
    )
  ));

DROP POLICY IF EXISTS "Users can leave coven" ON public.coven_members;
CREATE POLICY "Users can leave coven" ON public.coven_members
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- coven_resources table
DROP POLICY IF EXISTS "Members can view coven resources" ON public.coven_resources;
CREATE POLICY "Members can view coven resources" ON public.coven_resources
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_resources.coven_id AND player_id = auth.uid()
    )
  ));

DROP POLICY IF EXISTS "Leaders can update coven resources" ON public.coven_resources;
CREATE POLICY "Leaders can update coven resources" ON public.coven_resources
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_resources.coven_id AND player_id = auth.uid() AND role = 'leader'
    )
  ))
  WITH CHECK (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_resources.coven_id AND player_id = auth.uid() AND role = 'leader'
    )
  ));

-- coven_task_progress table
DROP POLICY IF EXISTS "Coven members can view task progress" ON public.coven_task_progress;
CREATE POLICY "Coven members can view task progress" ON public.coven_task_progress
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      JOIN public.coven_tasks ct ON ct.coven_id = cm.coven_id
      WHERE ct.id = coven_task_progress.task_id AND cm.player_id = auth.uid()
    )
  ));

DROP POLICY IF EXISTS "Coven members can update own contributions" ON public.coven_task_progress;
CREATE POLICY "Coven members can update own contributions" ON public.coven_task_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- coven_tasks table
DROP POLICY IF EXISTS "Coven members can view tasks" ON public.coven_tasks;
CREATE POLICY "Coven members can view tasks" ON public.coven_tasks
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id AND player_id = auth.uid()
    )
  ));

DROP POLICY IF EXISTS "Leaders and elders can update tasks" ON public.coven_tasks;
CREATE POLICY "Leaders and elders can update tasks" ON public.coven_tasks
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id AND player_id = auth.uid() AND role IN ('leader', 'elder')
    )
  ))
  WITH CHECK (auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id AND player_id = auth.uid() AND role IN ('leader', 'elder')
    )
  ));

-- crops table
DROP POLICY IF EXISTS "Enable read access for authenticated users on crops" ON public.crops;
CREATE POLICY "Enable read access for authenticated users on crops" ON public.crops
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- decoration_types table
DROP POLICY IF EXISTS "Anyone can view decoration types" ON public.decoration_types;
CREATE POLICY "Anyone can view decoration types" ON public.decoration_types
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- decorations table
DROP POLICY IF EXISTS "Anyone can view decorations" ON public.decorations;
CREATE POLICY "Anyone can view decorations" ON public.decorations
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Players can update own decorations" ON public.decorations;
CREATE POLICY "Players can update own decorations" ON public.decorations
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id)
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own decorations" ON public.decorations;
CREATE POLICY "Players can delete own decorations" ON public.decorations
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND auth.uid() = player_id);

-- factories table
DROP POLICY IF EXISTS "Users view own factories" ON public.factories;
CREATE POLICY "Users view own factories" ON public.factories
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users update own factories" ON public.factories;
CREATE POLICY "Users update own factories" ON public.factories
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users delete own factories" ON public.factories;
CREATE POLICY "Users delete own factories" ON public.factories
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- factory_queue table
DROP POLICY IF EXISTS "Users view own factory_queue" ON public.factory_queue;
CREATE POLICY "Users view own factory_queue" ON public.factory_queue
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users update own factory_queue" ON public.factory_queue;
CREATE POLICY "Users update own factory_queue" ON public.factory_queue
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users delete own factory_queue" ON public.factory_queue;
CREATE POLICY "Users delete own factory_queue" ON public.factory_queue
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- farm_plots table
DROP POLICY IF EXISTS "Users view own farm plots" ON public.farm_plots;
CREATE POLICY "Users view own farm plots" ON public.farm_plots
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users update own farm plots" ON public.farm_plots;
CREATE POLICY "Users update own farm plots" ON public.farm_plots
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users delete own farm plots" ON public.farm_plots;
CREATE POLICY "Users delete own farm plots" ON public.farm_plots
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- friend_help table
DROP POLICY IF EXISTS "Players can view own help" ON public.friend_help;
CREATE POLICY "Players can view own help" ON public.friend_help
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (auth.uid() = helper_id OR auth.uid() = helped_id));

-- friends table
DROP POLICY IF EXISTS "Players can view own friendships" ON public.friends;
CREATE POLICY "Players can view own friendships" ON public.friends
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (player_id = auth.uid() OR friend_id = auth.uid()));

DROP POLICY IF EXISTS "Players can update own friendships" ON public.friends;
CREATE POLICY "Players can update own friendships" ON public.friends
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND (player_id = auth.uid() OR friend_id = auth.uid()))
  WITH CHECK (auth.uid() IS NOT NULL AND (player_id = auth.uid() OR friend_id = auth.uid()));

DROP POLICY IF EXISTS "Players can delete own friendships" ON public.friends;
CREATE POLICY "Players can delete own friendships" ON public.friends
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND (player_id = auth.uid() OR friend_id = auth.uid()));

-- inventory table
DROP POLICY IF EXISTS "Users can view own inventory" ON public.inventory;
CREATE POLICY "Users can view own inventory" ON public.inventory
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own inventory" ON public.inventory;
CREATE POLICY "Users can update own inventory" ON public.inventory
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own inventory" ON public.inventory;
CREATE POLICY "Users can delete own inventory" ON public.inventory
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- market_listings table
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.market_listings;
CREATE POLICY "Anyone can view active listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND purchased_at IS NULL AND expires_at > now());

DROP POLICY IF EXISTS "Players can view own listings" ON public.market_listings;
CREATE POLICY "Players can view own listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND seller_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own listings" ON public.market_listings;
CREATE POLICY "Players can update own listings" ON public.market_listings
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND seller_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND seller_id = auth.uid());

DROP POLICY IF EXISTS "Players can delete own listings" ON public.market_listings;
CREATE POLICY "Players can delete own listings" ON public.market_listings
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND seller_id = auth.uid());

-- marketplace table
DROP POLICY IF EXISTS "Anyone can view marketplace" ON public.marketplace;
CREATE POLICY "Anyone can view marketplace" ON public.marketplace
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- mine_digs table
DROP POLICY IF EXISTS "Players can view own digs" ON public.mine_digs;
CREATE POLICY "Players can view own digs" ON public.mine_digs
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own digs" ON public.mine_digs;
CREATE POLICY "Players can update own digs" ON public.mine_digs
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- mining_tools table
DROP POLICY IF EXISTS "Players can view own tools" ON public.mining_tools;
CREATE POLICY "Players can view own tools" ON public.mining_tools
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own tools" ON public.mining_tools;
CREATE POLICY "Players can update own tools" ON public.mining_tools
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- notification_preferences table
DROP POLICY IF EXISTS "Players can view own preferences" ON public.notification_preferences;
CREATE POLICY "Players can view own preferences" ON public.notification_preferences
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own preferences" ON public.notification_preferences;
CREATE POLICY "Players can update own preferences" ON public.notification_preferences
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- ore_types table
DROP POLICY IF EXISTS "Anyone can view ore types" ON public.ore_types;
CREATE POLICY "Anyone can view ore types" ON public.ore_types
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- player_achievements table
DROP POLICY IF EXISTS "Players can view own achievements" ON public.player_achievements;
CREATE POLICY "Players can view own achievements" ON public.player_achievements
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own achievements" ON public.player_achievements;
CREATE POLICY "Players can update own achievements" ON public.player_achievements
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- premium_shop table
DROP POLICY IF EXISTS "Anyone can view premium shop" ON public.premium_shop;
CREATE POLICY "Anyone can view premium shop" ON public.premium_shop
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- profiles table
DROP POLICY IF EXISTS "Users view own profile" ON public.profiles;
CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND id = auth.uid());

DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND id = auth.uid());

-- push_subscriptions table
DROP POLICY IF EXISTS "Players can view own subscriptions" ON public.push_subscriptions;
CREATE POLICY "Players can view own subscriptions" ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own subscriptions" ON public.push_subscriptions;
CREATE POLICY "Players can update own subscriptions" ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can delete own subscriptions" ON public.push_subscriptions;
CREATE POLICY "Players can delete own subscriptions" ON public.push_subscriptions
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- quest_progress table
DROP POLICY IF EXISTS "Players can view own quest progress" ON public.quest_progress;
CREATE POLICY "Players can view own quest progress" ON public.quest_progress
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own quest progress" ON public.quest_progress;
CREATE POLICY "Players can update own quest progress" ON public.quest_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- quests table
DROP POLICY IF EXISTS "Anyone can view quests" ON public.quests;
CREATE POLICY "Anyone can view quests" ON public.quests
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- recipes table
DROP POLICY IF EXISTS "Enable read access for authenticated users on recipes" ON public.recipes;
CREATE POLICY "Enable read access for authenticated users on recipes" ON public.recipes
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- regatta_events table
DROP POLICY IF EXISTS "Anyone can view regattas" ON public.regatta_events;
CREATE POLICY "Anyone can view regattas" ON public.regatta_events
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND status IN ('upcoming', 'active'));

-- regatta_participants table
DROP POLICY IF EXISTS "Players can view own participation" ON public.regatta_participants;
CREATE POLICY "Players can view own participation" ON public.regatta_participants
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND (player_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = regatta_participants.coven_id AND player_id = auth.uid()
  )));

DROP POLICY IF EXISTS "Players can update own participation" ON public.regatta_participants;
CREATE POLICY "Players can update own participation" ON public.regatta_participants
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- regatta_task_submissions table
DROP POLICY IF EXISTS "Players can view own submissions" ON public.regatta_task_submissions;
CREATE POLICY "Players can view own submissions" ON public.regatta_task_submissions
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- roads table
DROP POLICY IF EXISTS "Users can view their own roads" ON public.roads;
CREATE POLICY "Users can view their own roads" ON public.roads
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users can update their own roads" ON public.roads;
CREATE POLICY "Users can update their own roads" ON public.roads
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their own roads" ON public.roads;
CREATE POLICY "Users can delete their own roads" ON public.roads
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- seed_shop table
DROP POLICY IF EXISTS "Anyone can view seed shop" ON public.seed_shop;
CREATE POLICY "Anyone can view seed shop" ON public.seed_shop
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

-- skyport_orders table
DROP POLICY IF EXISTS "Players can view own orders" ON public.skyport_orders;
CREATE POLICY "Players can view own orders" ON public.skyport_orders
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own orders" ON public.skyport_orders;
CREATE POLICY "Players can update own orders" ON public.skyport_orders
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- speed_ups table
DROP POLICY IF EXISTS "Players can view own speed-ups" ON public.speed_ups;
CREATE POLICY "Players can view own speed-ups" ON public.speed_ups
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can delete own speed-ups" ON public.speed_ups;
CREATE POLICY "Players can delete own speed-ups" ON public.speed_ups
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- town_expansions table
DROP POLICY IF EXISTS "Players can view own expansions" ON public.town_expansions;
CREATE POLICY "Players can view own expansions" ON public.town_expansions
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- warehouse_upgrades table
DROP POLICY IF EXISTS "Players can view own upgrades" ON public.warehouse_upgrades;
CREATE POLICY "Players can view own upgrades" ON public.warehouse_upgrades
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own upgrades" ON public.warehouse_upgrades;
CREATE POLICY "Players can update own upgrades" ON public.warehouse_upgrades
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

-- zoo_enclosures table
DROP POLICY IF EXISTS "Players can view own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can view own enclosures" ON public.zoo_enclosures
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can update own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can update own enclosures" ON public.zoo_enclosures
  FOR UPDATE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid())
  WITH CHECK (auth.uid() IS NOT NULL AND player_id = auth.uid());

DROP POLICY IF EXISTS "Players can delete own enclosures" ON public.zoo_enclosures;
CREATE POLICY "Players can delete own enclosures" ON public.zoo_enclosures
  FOR DELETE TO authenticated
  USING (auth.uid() IS NOT NULL AND player_id = auth.uid());

