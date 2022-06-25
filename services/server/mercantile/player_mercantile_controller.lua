local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
local mercantile_constants = constants.mercantile

local PlayerMercantile = class()

function PlayerMercantile:initialize()
   -- generated each morning based on settings/conditions at that time
   -- as each one is spawned, it's removed from the list
   self._sv._merchants_to_spawn = {}    -- list of merchants to spawn for this town

   -- merchant entities will only spawn if a stall could initially be assigned to them
   -- otherwise, or if something happens to their stall, their ai will have them hang out by the fire
   -- merchant entities will have a merchant component modeled after shop component
   self._sv.active_merchants = {}

   self._sv.category_preferences = {}   -- keyed by category, with a value from constants for disabled, enabled, encouraged
   self._sv.unique_preferences = {}     -- keyed by unique merchant id, with a boolean value for disabled/enabled
   self._sv.unique_cooldowns = {}       -- keyed by unique merchant id, with a game time when that merchant will no longer be on cd
   self._sv.unique_merchants = {}       -- keyed by unique merchant id, an indicator for whether they should show up in the ui

   self._sv.tier_stalls = {}            -- keyed by tier number, gives count for each
   self._sv.unique_stalls = {}          -- keyed by uri, gives count for each

   self._sv.max_disables = 0
   self._sv.max_encourages = 0

   self._merchant_stalls = {}
end

function PlayerMercantile:create(player_id, enabled)
   self._sv.player_id = player_id
   self:set_enabled(enabled)
end

function PlayerMercantile:restore()
   -- when we restore, we want to make sure the stall counts are all reset
   -- since those will get populated as the stalls themselves load
   self._sv.tier_stalls = {}
   self._sv.unique_stalls = {}
end

function PlayerMercantile:post_activate()
   self:_create_city_tier_listener()

   self:_start_spawn_timer_on_load()
end

function PlayerMercantile:set_enabled(enabled)
   self._sv.enabled = not not enabled
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:register_merchant_stall(stall)
   self._merchant_stalls[stall:get_id()] = stall

   local uri = stall:get_uri()
   local stall_data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:market_stall')
   if stall_data and stall_data.tier then
      local tier_stalls = self._sv.tier_stalls
      tier_stalls[stall_data.tier] = (tier_stalls[stall_data.tier] or 0) + 1
   end

   local unique_stalls = self._sv.unique_stalls
   unique_stalls[uri] = (unique_stalls[uri] or 0) + 1

   self.__saved_variables:mark_changed()
end

function PlayerMercantile:unregister_merchant_stall(stall)
   self._merchant_stalls[stall:get_id()] = nil

   local uri = stall:get_uri()
   local stall_data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:market_stall')
   if stall_data and stall_data.tier then
      local tier_stalls = self._sv.tier_stalls
      if tier_stalls[stall_data.tier] then
         tier_stalls[stall_data.tier] = tier_stalls[stall_data.tier] - 1
      end
   end

   local unique_stalls = self._sv.unique_stalls
   if unique_stalls[uri] then
      unique_stalls[uri] = unique_stalls[uri] - 1
   end

   self.__saved_variables:mark_changed()
end

function PlayerMercantile:reduce_unique_merchant_cooldowns()
   local cds = self._sv.unique_cooldowns
   for unique, cd in pairs(cds) do
      if cd > 1 then
         cds[unique] = cd - 1
      else
         cds[unique] = nil
      end
   end
end

function MercantileService:create_spawn_timer()
   local player_id = self._sv.player_id
   if self._sv.enabled and not self._spawning_timer and stonehearth.presence:is_player_connected(player_id) then
      local pop = stonehearth.population:get_population(player_id)
      if pop:get_city_tier() >= stonehearth.constants.merchant.MIN_CITY_TIER then
         local merchants_to_spawn = self:_get_merchants_to_spawn()
         if merchants_to_spawn and next(merchants_to_spawn) then
            self._spawning_timer = self:_create_spawn_timer()
         end
      end
   end
end

function MercantileService:_start_spawn_timer_on_load()
   if #self._sv._merchants_to_spawn > 0 and self._sv.enabled then
      -- if the current time is already past the depart time, cancel the whole thing
      local now = stonehearth.calendar:get_seconds_since_last_midnight()
      local depart_time = stonehearth.calendar:parse_time(mercantile_constants.DEPART_TIME)
      if now >= depart_time then
         self._sv._merchants_to_spawn = {}
      else
         self._spawning_timer = self:_create_spawn_timer()
      end
   end
end

function PlayerMercantile:_create_spawn_timer()
   local player_id = self._sv.player_id
   local town = stonehearth.town:get_town(player_id)
   return stonehearth.calendar:set_interval('towns merchant spawner', '5m+20m', function()
      local merchant_data = table.remove(self._sv._merchants_to_spawn)
      local merchant = town:spawn_traveler()
         if not self._sv._seen_bulletin then
         stonehearth.bulletin_board:post_bulletin(player_id)
            :set_ui_view('StonehearthGenericBulletinDialog')
            :set_callback_instance(self)
            :set_data({
               title = 'i18n(stonehearth_ace:ui.game.bulletin.merchant.first.title)',
               message = 'i18n(stonehearth_ace:ui.game.bulletin.merchant.first.message)',
               zoom_to_entity = merchant,
               ok_callback = '_on_bulletin_ok',
            })
            :add_i18n_data('merchant_name', radiant.entities.get_custom_name(merchant))
            :add_i18n_data('shop_name')
         self._sv._seen_bulletin = true
         end
         self._sv._merchants_to_spawn[player_id] = self._sv._merchants_to_spawn[player_id] - 1
         if self._sv._merchants_to_spawn[player_id] <= 0 then
            if self._spawning_timers[player_id] then
                  self._spawning_timers[player_id]:destroy()
                  self._spawning_timers[player_id] = nil
            end
         end
      end)
end

function PlayerMercantile:_on_bulletin_ok()
   -- probably don't even need this
end

function PlayerMercantile:_destroy_city_tier_listener()
   if self._city_tier_listener then
      self._city_tier_listener:destroy()
      self._city_tier_listener = nil
   end
end

function PlayerMercantile:_create_city_tier_listener()
   self:_destroy_city_tier_listener()

   self._city_tier_listener = radiant.events.listen(stonehearth.population:get_population(self._sv.player_id), 'stonehearth_ace:city_tier_changed',
      function(args)
         if args.player_id == self._sv.player_id then
            -- this player's city tier has changed! update max disables/encourages
            self:_update_city_tier()
         end
      end

   self:_update_city_tier()
end

function PlayerMercantile:_update_city_tier()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   local city_tier = pop:get_city_tier()
   
   -- in case it's not specified for this tier, use the closest lower specified tier
   local max_disables
   for tier = city_tier, 1, -1 do
      local max_disables = mercantile_constants.MAX_DISABLES_PER_TIER[tier]
      if max_disables then
         break
      end
   end
   self._sv.max_disables = max_disables or 0

   local max_encourages
   for tier = city_tier, 1, -1 do
      local max_encourages = mercantile_constants.MAX_ENCOURAGES_PER_TIER[tier]
      if max_encourages then
         break
      end
   end
   self._sv.max_encourages = max_encourages or 0

   -- make sure we're not going over with our current preferences
   local num_disables = 0
   local num_encourages = 0
   local category_preferences = self._sv.category_preferences
   for category, pref in pairs(category_preferences) do
      if pref == mercantile_constants.category_preferences.DISABLED then
         num_disables = num_disables + 1
         if num_disables > max_disables then
            category_preferences[category] = mercantile_constants.category_preferences.ENABLED
         end
      elseif pref == mercantile_constants.category_preferences.ENCOURAGED then
         num_encourages = num_encourages + 1
         if num_encourages > max_encourages then
            category_preferences[category] = mercantile_constants.category_preferences.ENABLED
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function PlayerMercantile:_get_merchants_to_spawn()
   -- determine which merchants to spawn and store them in _sv

   local num_spawned = 0
   local num_merchants = self:_calculate_num_merchants()
   self._sv.max_daily_merchants = num_merchants
   
   if num_merchants > 0 then
      -- first load up the possible merchant stalls they could use
      -- if there are no stalls, we only want to get a single merchant and have them hang out by the fire
      local stalls = self._sv.unique_stalls
      local has_stalls = next(stalls) ~= nil
      if not has_stalls then
         num_merchants = 1
      end

      local pop = stonehearth.population:get_population(self._sv.player_id)
      local city_tier = pop:get_city_tier()

      local merchants = {}
      -- generate bags of merchants to draw from and then draw them until we've reached num_merchants
      -- first get as many unique merchants as we can (skip if no stalls)
      if has_stalls then
         local used_stalls = {}
         local uniques = self:_get_available_unique_merchants(stalls, city_tier)
         
         while num_merchants > 0 and not uniques:is_empty() do
            local merchant = uniques:choose_random()
            uniques:remove(merchant)
            -- make sure we still have a stall that can support this merchant
            local uri = merchant.required_stall
            if stalls[uri] > (used_stalls[uri] or 0) then
               merchants[merchant.key] = merchant
               num_merchants = num_merchants - 1
               used_stalls[uri] = (used_stalls[uri] or 0) + 1
            end
         end
      end

      -- populate highest tier stalls first
      if num_merchants > 0 then
         stalls = self._sv.tier_stalls
         for tier = #stalls, 1, -1 do
            local used = 0
            local available = stalls[tier] or 0
            if num_merchants > 0 and available > used then
               local category_merchants = self:_get_available_category_merchants(tier, city_tier)
               
               while num_merchants > 0 and available > used and not category_merchants:is_empty() do
                  local merchant = category_merchants:choose_random()
                  category_merchants:remove(merchant)
                  -- make sure we didn't get this same merchant already
                  if not merchants[merchant.key] then
                     merchants[merchant.key] = merchant
                     num_merchants = num_merchants - 1
                     used = used + 1
                  end
               end
            end
         end
      end

      num_spawned = radiant.size(merchants)
   end

   -- transform merchants table into a shuffled list
   local merchants_list = {}
   for id, merchant in pairs(merchants) do
      table.insert(merchants_list, rng:get_int(1, #merchants_list + 1), merchant)
   end

   self._sv._merchants_to_spawn = merchants_list
   self._sv.num_merchants_last_spawned = num_spawned

   return self._sv._merchants_to_spawn
end

-- function PlayerMercantile:_create_weighted_set(list)
--    local set = WeightedSet(rng)
--    for _, item in ipairs(list) do
--       set:add(item, item.weight or 1)
--    end
--    return set
-- end

-- function PlayerMercantile:_get_available_merchant_stalls()
--    local stalls = {
--       tier = {},  -- keyed by tier #, provides # of stalls of that tier
--       uri = {}, -- keyed by uri, provides # of stalls of that type
--    }

--    for id, stall in pairs(self._merchant_stalls) do
--       local uri = stall:get_uri()
--       local stall_data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:market_stall')
--       if stall_data and stall_data.tier then
--          stalls.tier[stall_data.tier] = (stalls.tier[stall_data.tier] or 0) + 1
--       end
--       stalls.uri[uri] = (stalls.uri[uri] or 0) + 1
--    end

--    return stalls
-- end

-- returns a weighted set of available unique merchants
function PlayerMercantile:_get_available_unique_merchants(stall_uris, city_tier)
   local unique_merchants = stonehearth_ace.mercantile:get_unique_merchants()
   local uniques = WeightedSet(rng)
   for unique, merchant in pairs(unique_merchants) do
      if self._sv.unique_preferences[unique] ~= false and not self._sv.unique_cooldowns[unique] and
            (merchant.min_city_tier or 1) >= city_tier and stall_uris[merchant.required_stall] then
         uniques:add(merchant, merchant.weight)
      end
   end
   return uniques
end

-- returns a weighted set of available category merchants
function PlayerMercantile:_get_available_category_merchants(stall_tier, city_tier)
   local categories = stonehearth_ace.mercantile:get_category_merchants()
   local set = WeightedSet(rng)
   for category, category_merchants in pairs(categories) do
      local cat_min_city_tier = stonehearth_ace.mercantile:get_category_min_city_tier(category)
      if city_tier >= cat_min_city_tier then
         local pref = self._sv.category_preferences[category]
         if pref ~= mercantile_constants.category_preferences.DISABLED then
            for merchant, merchant_data in pairs(category_merchants) do
               if (merchant_data.min_city_tier or 1) >= city_tier and (merchant_data.min_stall_tier or 1) <= stall_tier then
                  local weight = merchant.weight
                  if pref == mercantile_constants.category_preferences.ENCOURAGED then
                     weight = weight * mercantile_constants.ENCOURAGED_MULTIPLIER
                  end
                  set:add(merchant, weight)
               end
            end
         end
      end
   end
   return merchants
end

function PlayerMercantile:_calculate_num_merchants()
   local player_id = self._sv.player_id
   local inventory = stonehearth.inventory:get_inventory(player_id)
   if not inventory then
      return 0
   end

   local traded = (inventory:get_trade_gold_earned() + inventory:get_trade_gold_spent()) *
         (mercantile_constants.TOTAL_TRADE_MUTLIPLIER or 1)

   local score_data = stonehearth.score:get_scores_for_player(player_id)
                              :get_score_data()
   local net_worth = 0
   if score_data and score_data.total_scores:contains('net_worth') then
      net_worth = (score_data.total_scores:get('net_worth') or 0) *
            (mercantile_constants.NET_WORTH_MUTLIPLIER or 1)
   end

   -- = log ( coefficient * net worth + coefficient * traded)
   local sum = net_worth + traded
   if sum > 0 then
      -- math.log(1 + sum) so we're always getting a positive result from log (log(1) == 0)
      local num_merchants = math.max(0, math.log(1 + sum) + (mercantile_constants.ADDITIVE_MODIFIER or 0))
      if num_merchants > 0 then
         -- it probably won't be less than 1 for very long, so we can just do normal chance with that
         -- if > 1, guarantee the integer amount of merchants and then randomize on the remainder
         local int_num_merchants, remainder = math.modf(num_merchants)
         if rng:get_real(0, 1) <= remainder then
            int_num_merchants = int_num_merchants + 1
         end
         return int_num_merchants
      end
   else
      return 0
   end
end

return PlayerMercantile
