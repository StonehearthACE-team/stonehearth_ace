local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
local mercantile_constants = constants.mercantile
local game_mode_modifier

local PlayerMercantile = class()

function PlayerMercantile:initialize()
   -- generated each morning based on settings/conditions at that time
   -- as each one is spawned, it's removed from the list
   self._sv._merchants_to_spawn = {}    -- list of merchants to spawn for this town
   self._sv._merchants_to_depart = {}   -- list of merchants who need to depart this town
   self._sv._departing_merchant_ids = {}  -- list of ids of merchants already instructed to depart

   -- merchant entities will only spawn if a stall could initially be assigned to them
   -- otherwise, or if something happens to their stall, their ai will have them hang out by the fire
   -- merchant entities will have a merchant component modeled after shop component
   self._sv.active_merchants = {}

   self._sv.category_preferences = {}   -- keyed by category, with a value from constants for disabled, enabled, encouraged
   self._sv.cooldowns = {}              -- keyed by merchant id, with a game time when that merchant will no longer be on cd
   self._sv.exclusive_preferences = {}     -- keyed by exclusive merchant id, with a boolean value for disabled/enabled
   --self._sv.exclusive_merchants = {}       -- keyed by exclusive merchant id, an indicator for whether they should show up in the ui

   self._sv.tier_stalls = {}            -- keyed by tier number, gives count for each
   self._sv.exclusive_stalls = {}          -- keyed by uri, gives count for each
   self._sv.num_stalls = 0

   self._sv.max_disables = 0
   self._sv.max_encourages = 0

   self._sv.max_daily_merchants = 0
   self._sv.num_merchants_last_spawned = 0

   self._merchant_stalls = {}
end

function PlayerMercantile:create(player_id, enabled)
   self._sv.player_id = player_id
   self:set_enabled(enabled)
end

function PlayerMercantile:restore()
   -- when we restore, we want to make sure the stall counts are all reset
   -- since those will get populated as the stalls themselves load
   -- (they're only in _sv so they get shown in the client ui)
   self._sv.tier_stalls = {}
   self._sv.exclusive_stalls = {}
   self._sv.num_stalls = 0
end

function PlayerMercantile:post_activate()
   self:_create_city_tier_listener()

   self._kingdom_uri = stonehearth.population:get_population(self._sv.player_id):get_kingdom()

   self:_start_depart_timer()
end

function PlayerMercantile:destroy()
   self:_destroy_spawning_timer()
   self:_destroy_depart_timer()
   self:_depart_all_merchants()
end

function PlayerMercantile:_destroy_spawning_timer()
   if self._spawning_timer then
      self._spawning_timer:destroy()
      self._spawning_timer = nil
   end
end

function PlayerMercantile:_destroy_depart_timer()
   if self._depart_timer then
      self._depart_timer:destroy()
      self._depart_timer = nil
   end
end

function PlayerMercantile:_depart_all_merchants()
   local merchants = self:_get_all_undeparted_merchants()
   for _, merchant in pairs(merchants) do
      self:_depart_merchant(merchant)
   end
   self._sv._merchants_to_depart = {}
end

function PlayerMercantile:set_enabled(enabled)
   self._sv.enabled = not not enabled
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:register_merchant_stall(stall)
   self._merchant_stalls[stall:get_id()] = stall
   self:_recompute_num_stalls()
end

function PlayerMercantile:unregister_merchant_stall(stall)
   self._merchant_stalls[stall:get_id()] = nil
   self:_recompute_num_stalls()
end

function PlayerMercantile:_recompute_num_stalls()
   -- for some reason keeping track of it with +1/-1 on register/unregister was unreliable?
   -- shouldn't be more than a dozen or so stalls though, so it's fine to recheck all
   -- (and infrequent changes besides reload)
   local tier_stalls = {
      [1] = 0,
      [2] = 0,
      [3] = 0,
   }
   local exclusive_stalls = {}
   local num_stalls = 0
   for id, stall in pairs(self._merchant_stalls) do
      local stall_component = stall:get_component('stonehearth_ace:market_stall')
      if stall_component then
         local uri = stall:get_uri()
         local tier = stall_component:get_tier()
         if tier then
            tier_stalls[tier] = tier_stalls[tier] + 1
         else
            exclusive_stalls[uri] = (exclusive_stalls[uri] or 0) + 1
         end
         num_stalls = num_stalls + 1
      end
   end

   self._sv.tier_stalls = tier_stalls
   self._sv.exclusive_stalls = exclusive_stalls
   self._sv.num_stalls = num_stalls
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:remove_merchant(merchant)
   local id = merchant:get_id()
   self._sv.active_merchants[id] = nil
   self._sv._departing_merchant_ids[id] = nil
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:reduce_merchant_cooldowns()
   local cds = self._sv.cooldowns
   for id, cd in pairs(cds) do
      if cd > 1 then
         cds[id] = cd - 1
      else
         cds[id] = nil
      end
   end
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:depart_active_merchants()
   -- similar to spawning the merchants initially, set up a timer to arbitrarily do one at a time
   self:_get_all_undeparted_merchants()
   self:_start_depart_timer()
end

function PlayerMercantile:_get_all_undeparted_merchants()
   -- create lookup so we're not trying to double-depart
   local departing_merchants = {}
   for _, merchant in ipairs(self._sv._merchants_to_depart) do
      departing_merchants[merchant:get_id()] = merchant
   end

   for id, merchant in pairs(self._sv.active_merchants) do
      if not departing_merchants[id] and not self._sv._departing_merchant_ids[id] then
         table.insert(self._sv._merchants_to_depart, merchant)
      end
   end

   return self._sv._merchants_to_depart
end

function PlayerMercantile:_create_depart_timer()
   self:_destroy_depart_timer()

   self._depart_timer = stonehearth.calendar:set_interval('towns merchant departer', '5m+15m', function()
         local merchant = table.remove(self._sv._merchants_to_depart)
         self._sv._departing_merchant_ids[merchant:get_id()] = true
         self:_depart_merchant(merchant)

         if #self._sv._merchants_to_depart <= 0 then
            self:_destroy_depart_timer()
         end
      end)
end

function PlayerMercantile:_depart_merchant(merchant)
   merchant:get_component('stonehearth_ace:merchant'):set_should_depart()
end

function PlayerMercantile:set_trade_preferences(category_preferences, exclusive_preferences)
   self._sv.category_preferences = category_preferences
   self:_verify_category_preferences()
   self._sv.exclusive_preferences = exclusive_preferences

   self.__saved_variables:mark_changed()
end

function PlayerMercantile:set_category_preference_command(session, response, category, preference)
   self._sv.category_preferences[category] = preference
   self:_verify_category_preferences()
   self.__saved_variables:mark_changed()
end

function PlayerMercantile:determine_daily_merchants()
   local player_id = self._sv.player_id
   if self._sv.enabled and not self._spawning_timer and stonehearth.presence:is_player_connected(player_id) then
      local pop = stonehearth.population:get_population(player_id)
      if pop:get_city_tier() >= mercantile_constants.MIN_CITY_TIER then
         local merchants_to_spawn = self:_determine_daily_merchants()
         if merchants_to_spawn and next(merchants_to_spawn) then
            self:_create_spawn_timer()
         end
      end
   end
end

function PlayerMercantile:_start_spawn_timer_on_load()
   if #self._sv._merchants_to_spawn > 0 and self._sv.enabled then
      -- if the current time is already past the depart time, cancel the whole thing
      local now = stonehearth.calendar:get_seconds_since_last_midnight()
      local depart_time = stonehearth.calendar:parse_time(mercantile_constants.DEPART_TIME)
      if now >= depart_time then
         self._sv._merchants_to_spawn = {}
      else
         self:_create_spawn_timer()
      end
   end
end

function PlayerMercantile:_start_depart_timer()
   if #self._sv._merchants_to_depart > 0 then
      self:_create_depart_timer()
   end
end

function PlayerMercantile:_create_spawn_timer()
   self:_destroy_spawning_timer()

   self._spawning_timer = stonehearth.calendar:set_interval('towns merchant spawner', '5m+20m', function()
         local merchant = self:_spawn_merchant(table.remove(self._sv._merchants_to_spawn))

         if not self._sv._seen_bulletin then
            stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
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
         if #self._sv._merchants_to_spawn <= 0 then
            self:_destroy_spawning_timer()
         end

         -- show the initial bulletin here so it's after the "first merchant" bulletin
         merchant:get_component('stonehearth_ace:merchant'):show_bulletin(true)
      end)
end

function PlayerMercantile:_spawn_merchant(merchant)
   local player_id = self._sv.player_id
   local town = stonehearth.town:get_town(player_id)
   local merchant_data = stonehearth_ace.mercantile:get_merchant_data(merchant)
   if town and merchant_data then
      local pop = stonehearth.population:get_population('human_npcs')
      local role = merchant_data.population_role or stonehearth.mercantile:get_default_population_role(merchant_data.category)
      local merchant = pop:create_new_citizen(role, merchant_data.population_gender)
      if merchant_data.equipment then
         local equipment_component = merchant:add_component('stonehearth:equipment')
         for _, uri in ipairs(merchant_data.equipment) do
            equipment_component:equip_item(uri)
         end
      end

      merchant:add_component('stonehearth_ace:merchant'):set_merchant_data(player_id, merchant_data)
      
      local cooldown = merchant_data.cooldown
      if cooldown then
         -- TODO: Dani maybe find a town bonus for this kind of feature?
         local mercantile_bonus = town:get_town_bonus('stonehearth_ace:town_bonus:mercantile')
         if mercantile_bonus then
            cooldown = mercantile_bonus:get_reduced_cooldown(cooldown)
         end
         if cooldown > 0 then
            self._sv.cooldowns[merchant_data.key] = cooldown
         end
      end
      self._sv.active_merchants[merchant:get_id()] = merchant
      self.__saved_variables:mark_changed()

      local town_landing_location = town:get_landing_location()
      local location = radiant.terrain.find_placement_point(town_landing_location, 1, 15)

      radiant.terrain.place_entity(merchant, location)

      stonehearth.ai:inject_ai(merchant, { task_groups = { "stonehearth_ace:task_groups:merchant" } })
      radiant.effects.run_effect(merchant, 'stonehearth:effects:spawn_entity')

      return merchant
   end
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
      end)

   self:_update_city_tier()
end

function PlayerMercantile:_update_city_tier()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   local city_tier = pop:get_city_tier()
   
   -- in case it's not specified for this tier, use the closest lower specified tier
   local max_disables
   for tier = city_tier, 1, -1 do
      max_disables = mercantile_constants.MAX_DISABLES_PER_TIER[tier]
      if max_disables then
         break
      end
   end
   self._sv.max_disables = max_disables or 0

   local max_encourages
   for tier = city_tier, 1, -1 do
      max_encourages = mercantile_constants.MAX_ENCOURAGES_PER_TIER[tier]
      if max_encourages then
         break
      end
   end
   self._sv.max_encourages = max_encourages or 0

   self:_verify_category_preferences()

   self.__saved_variables:mark_changed()
end

function PlayerMercantile:_verify_category_preferences()
   -- make sure we're not going over with our current preferences
   local num_disables = 0
   local num_encourages = 0
   local category_preferences = self._sv.category_preferences
   for category, pref in pairs(category_preferences) do
      if pref == mercantile_constants.category_preferences.DISABLED then
         num_disables = num_disables + 1
         if num_disables > self._sv.max_disables then
            num_disables = num_disables - 1
            category_preferences[category] = mercantile_constants.category_preferences.ENABLED
         end
      elseif pref == mercantile_constants.category_preferences.ENCOURAGED then
         num_encourages = num_encourages + 1
         if num_encourages > self._sv.max_encourages then
            num_encourages = num_encourages - 1
            category_preferences[category] = mercantile_constants.category_preferences.ENABLED
         end
      end
   end

   self._sv.num_disables = num_disables
   self._sv.num_encourages = num_encourages
end

function PlayerMercantile:_determine_daily_merchants()
   -- determine which merchants to spawn and store them in _sv

   local num_merchants, max_daily = self:_calculate_num_merchants()
   -- save the actual float amount so the ui can say something like "daily merchants: 2-3"
   self._sv.max_daily_merchants = max_daily or num_merchants
   
   self._sv._merchants_to_spawn = self:_get_merchants_to_spawn(num_merchants)
   self._sv.num_merchants_last_spawned = #self._sv._merchants_to_spawn
   self.__saved_variables:mark_changed()

   return self._sv._merchants_to_spawn
end

function PlayerMercantile:_get_merchants_to_spawn(num_merchants)
   local merchants_list = {}
   
   if num_merchants > 0 then
      local merchants = {}

      -- first load up the possible merchant stalls they could use
      -- if there are no stalls, we only want to get a single merchant and have them hang out by the fire
      self._sv.limited_by_stalls = self._sv.num_stalls < num_merchants
      local has_stalls = self._sv.num_stalls > 0
      if not has_stalls then
         num_merchants = 1
      end

      local pop = stonehearth.population:get_population(self._sv.player_id)
      local city_tier = pop:get_city_tier()
      local cur_weather = stonehearth.weather:get_current_weather()
      local cur_weather_uri = cur_weather and cur_weather:get_uri()

      -- generate bags of merchants to draw from and then draw them until we've reached num_merchants
      -- first get as many exclusive merchants as we can (skip if no exclusive stalls)
      local stalls = self._sv.exclusive_stalls
      if next(stalls) then
         local used_stalls = {}
         local exclusives = self:_get_available_exclusive_merchants(cur_weather_uri, stalls, city_tier)
         
         while num_merchants > 0 and not exclusives:is_empty() do
            local merchant = exclusives:choose_random()
            exclusives:remove(merchant)
            -- make sure we still have a stall that can support this merchant
            local uri = merchant.required_stall
            if stalls[uri] > (used_stalls[uri] or 0) then
               merchants[merchant] = true
               num_merchants = num_merchants - 1
               used_stalls[uri] = (used_stalls[uri] or 0) + 1
            end
         end
      end

      -- populate highest tier stalls first
      if num_merchants > 0 then
         stalls = self._sv.tier_stalls
         local max_tier = has_stalls and mercantile_constants.MAX_STALL_TIER or 1
         for tier = max_tier, 1, -1 do
            local used = 0
            local available = stalls[tier] or 0
            if num_merchants > 0 and (available > used or not has_stalls) then
               local category_merchants = self:_get_available_category_merchants(cur_weather_uri, tier, city_tier)
               
               while num_merchants > 0 and (available > used or not has_stalls) and not category_merchants:is_empty() do
                  local merchant = category_merchants:choose_random()
                  category_merchants:remove(merchant)
                  -- make sure we didn't get this same merchant already from a higher tier
                  if not merchants[merchant] then
                     merchants[merchant] = true
                     num_merchants = num_merchants - 1
                     used = used + 1
                  end
               end
            end
         end
      end
      
      -- transform merchants table into a shuffled list
      for merchant, _ in pairs(merchants) do
         table.insert(merchants_list, rng:get_int(1, #merchants_list + 1), merchant)
      end
   end

   return merchants_list
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

-- returns a weighted set of available exclusive merchants
function PlayerMercantile:_get_available_exclusive_merchants(cur_weather_uri, stall_uris, city_tier)
   local exclusive_merchants = stonehearth_ace.mercantile:get_exclusive_merchants()
   local merchants = WeightedSet(rng)
   for merchant, merchant_data in pairs(exclusive_merchants) do
      if self._sv.exclusive_preferences[merchant] ~= false and merchant_data.min_city_tier >= city_tier and stall_uris[merchant_data.required_stall] then
         -- if this merchant's visit isn't forbidden by a cooldown, the kingdom, or the current weather, add them to the list
         if self:_merchant_allowed(merchant_data, cur_weather_uri) then
            merchants:add(merchant, merchant_data.weight)
         end
      end
   end
   return merchants
end

-- returns a weighted set of available category merchants
function PlayerMercantile:_get_available_category_merchants(cur_weather_uri, stall_tier, city_tier)
   local categories = stonehearth_ace.mercantile:get_category_merchants()
   local merchants = WeightedSet(rng)
   for category, category_merchants in pairs(categories) do
      local cat_min_city_tier = stonehearth_ace.mercantile:get_category_min_city_tier(category)
      if city_tier >= cat_min_city_tier then
         local pref = self._sv.category_preferences[category]
         if pref ~= mercantile_constants.category_preferences.DISABLED then
            for merchant, merchant_data in pairs(category_merchants) do
               if city_tier >= merchant_data.min_city_tier and merchant_data.min_stall_tier <= stall_tier then
                  -- if this merchant's visit isn't forbidden by a cooldown, the kingdom, or the current weather, add them to the list
                  if self:_merchant_allowed(merchant_data, cur_weather_uri) then
                     local weight = merchant_data.weight
                     if pref == mercantile_constants.category_preferences.ENCOURAGED then
                        weight = weight * mercantile_constants.ENCOURAGED_MULTIPLIER
                     end
                     merchants:add(merchant, weight)
                  end
               end
            end
         end
      end
   end
   return merchants
end

function PlayerMercantile:_merchant_allowed(merchant_data, cur_weather_uri)
   if self._sv.cooldowns[merchant_data.key] then
      return false
   end

   if self._kingdom_uri and ((merchant_data.forbidden_kingdom and merchant_data.forbidden_kingdom[self._kingdom_uri]) or
         (merchant_data.only_kingdom and not merchant_data.only_kingdom[self._kingdom_uri])) then
      return false
   end

   if cur_weather_uri and merchant_data.forbidden_weather and merchant_data.forbidden_weather[cur_weather_uri] then
      return false
   end

   return true
end

function PlayerMercantile:_calculate_num_merchants()
   local player_id = self._sv.player_id
   local inventory = stonehearth.inventory:get_inventory(player_id)
   if not inventory then
      self._sv.enabled = false
      self.__saved_variables:mark_changed()
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

   -- = (( coefficient * net worth + coefficient * traded) ^ (1/3) + modifier) * game_mode_modifier
   local sum = net_worth + traded
   if sum > 0 then
      local num_merchants = sum ^ (1/3) + (mercantile_constants.ADDITIVE_MODIFIER or 0)
      
      if not game_mode_modifier then
         local game_mode_json = stonehearth.game_creation:get_game_mode_json()
         game_mode_modifier = game_mode_json.merchant_chance_multiplier or 1
      end
      num_merchants = math.min(mercantile_constants.MAX_DAILY_MERCHANTS, num_merchants * game_mode_modifier)

      if num_merchants > 0 then
         -- it probably won't be less than 1 for very long, so we can just do normal chance with that
         -- if > 1, guarantee the integer amount of merchants and then randomize on the remainder
         local int_num_merchants, remainder = math.modf(num_merchants)
         if rng:get_real(0, 1) <= remainder then
            int_num_merchants = int_num_merchants + 1
         end
         return int_num_merchants, num_merchants
      end
   end

   return 0
end

return PlayerMercantile
