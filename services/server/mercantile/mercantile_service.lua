--[[
   modeled after stonehearth.traveler service:
   - handle the functionality of spawning merchants, bulletins, etc. here,
   - town/population controllers can still contain the factors for how many merchants to spawn
   - merchant stalls register with the town so those factors/capabilities can be computed there
      and easily shown through the town ui (settings will also get saved there)
]]

local validator = radiant.validator

local MercantileService = class()

local log = radiant.log.create_logger('mercantile_service')

function MercantileService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv._initialized then
      self._sv.players = {}
      
      -- make sure all non-npc players have a controller
      for player_id, _ in pairs(stonehearth.player:get_non_npc_players()) do
         self:add_player_controller(player_id, true)
      end

      self._sv._initialized = true
   end

   -- merchants can't spawn before a biome has been set, so don't bother loading merchants until then
   local biome_uri = stonehearth.world_generation:get_biome_alias()
   if not biome_uri then
      self._biome_listener = radiant.events.listen(radiant, 'stonehearth:biome_set', function(args)
            self:_load_merchant_data(args.biome_uri)
         end)
   else
      self:_load_merchant_data(biome_uri)
   end

   self._morning_spawn_alarm = stonehearth.calendar:set_alarm(stonehearth.constants.mercantile.SPAWN_TIME, function()
         self:_spawn_all_merchants()
      end)

   self._evening_depart_alarm = stonehearth.calendar:set_alarm(stonehearth.constants.mercantile.DEPART_TIME, function()
         for player_id, player_controller in pairs(self._sv.players) do
            player_controller:depart_active_merchants()
         end
         --radiant.events.trigger_async(self, 'stonehearth_ace:merchants:depart_time')
      end)

   self:_create_kingdom_assigned_listener()
end

function MercantileService:destroy()
   if self._morning_spawn_alarm then
      self._morning_spawn_alarm:destroy()
      self._morning_spawn_alarm = nil
   end
   if self._evening_depart_alarm then
      self._evening_depart_alarm:destroy()
      self._evening_depart_alarm = nil
   end
   if self._biome_listener then
      self._biome_listener:destroy()
      self._biome_listener = nil
   end
   if self._kingdom_assigned_listener then
      self._kingdom_assigned_listener:destroy()
      self._kingdom_assigned_listener = nil
   end
end

function MercantileService:_create_kingdom_assigned_listener()
   self._kingdom_assigned_listener = radiant.events.listen(radiant, 'radiant:player_kingdom_assigned', function(args)
         if not stonehearth.player:is_player_npc(args.player_id) then
            self:add_player_controller(args.player_id):update_kingdom()
         end
      end)
end

function MercantileService:get_player_controller(player_id)
   return self._sv.players[player_id]
end

function MercantileService:add_player_controller(player_id, start_enabled)
   local controller = self:get_player_controller(player_id)
   if not controller then
      -- if it's a non-npc player, start the controller enabled; otherwise start it disabled
      controller = radiant.create_controller('stonehearth_ace:player_mercantile_controller', player_id,
                                             start_enabled or stonehearth.player:get_non_npc_players()[player_id])
      self._sv.players[player_id] = controller
   end
   return controller
end

function MercantileService:remove_player(player_id)
   local controller = self:get_player_controller(player_id)
   if controller then
      controller:destroy()
      self._sv.players[player_id] = nil
   end
end

function MercantileService:get_categories()
   return self._categories
end

function MercantileService:get_category_merchants()
   return self._category_merchants
end

function MercantileService:get_exclusive_merchants()
   return self._exclusive_merchants
end

function MercantileService:get_merchant_data(merchant)
   return self._all_merchants and self._all_merchants[merchant]
end

function MercantileService:get_category_min_city_tier(category)
   local category_data = self._categories[category]
   return category_data and category_data.min_city_tier or 1
end

function MercantileService:get_default_population_role(category)
   local category_data = self._categories[category]
   return category_data and category_data.default_population_role or 'merchant'
end

function MercantileService:get_all_mercantile_data_command(session, response)
   response:resolve({
      categories = self._categories,
      merchants = self._all_merchants,
   })
end

function MercantileService:get_player_controller_command(session, response)
   response:resolve({controller = self:add_player_controller(session.player_id)})
end

function MercantileService:show_shop_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local merchant_component = self:_get_merchant_component(entity)
   local shop = self:_get_shop(merchant_component, session.player_id)
   if shop then
      merchant_component:show_bulletin()
   end
end

function MercantileService:get_shop_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local merchant_component = self:_get_merchant_component(entity)
   response:resolve({shop = self:_get_shop(merchant_component, session.player_id)})
end

function MercantileService:_get_merchant_component(entity)
   -- entity can be either a merchant or a stall
   -- the merchant component has the shop stored in it
   local merchant_component = entity:get_component('stonehearth_ace:merchant')
   if not merchant_component then
      local stall_component = entity:get_component('stonehearth_ace:market_stall')
      if stall_component then
         local merchant = stall_component:get_merchant()
         merchant_component = merchant and merchant:get_component('stonehearth_ace:merchant')
      end
   end

   return merchant_component
end

function MercantileService:_get_shop(merchant_component, player_id)
   -- make sure the shop is actually for the calling player
   if merchant_component and merchant_component:get_player_id() == player_id then
      return merchant_component:get_shop()
   end
end

function MercantileService:set_trade_preferences_command(session, response, categories, exclusives)
   local player_controller = self:get_player_controller(session.player_id)
   if player_controller then
      player_controller:set_trade_preferences(categories, exclusives)
   end
end

function MercantileService:register_merchant_stall(stall)
   if stall and stall:is_valid() then
      local player = self:add_player_controller(stall:get_player_id())
      player:register_merchant_stall(stall)
   end
end

function MercantileService:unregister_merchant_stall(stall)
   if stall and stall:is_valid() then
      local player = self:get_player_controller(stall:get_player_id())
      if player then
         player:unregister_merchant_stall(stall)
      end
   end
end

function MercantileService:remove_merchant(merchant)
   if merchant and merchant:is_valid() then
      local merchant_component = merchant:get_component('stonehearth_ace:merchant')
      if merchant_component then
         merchant_component:take_down_from_stall()
         local player = self:get_player_controller(merchant_component:get_player_id())
         if player then
            player:remove_merchant(merchant)
         end
      end
   end
end

function MercantileService:_load_merchant_data(biome_uri)
   -- deep copy the loaded table because we're going to be modifying it a lot
   local data = radiant.resources.load_json('stonehearth_ace:data:merchant_categories')
   local category_merchants = {}
   local exclusive_merchants = {}
   local all_merchants = {}

   for category, category_data in pairs(data.categories) do
      category_data.category = category
      local merchants = category_data.merchants and radiant.resources.load_json(category_data.merchants)
      if merchants and merchants.merchants then
         for merchant, merchant_data in pairs(merchants.merchants) do
            if self:_merchant_allowed_in_biome(merchant_data, biome_uri) then
               local copied_merchant_data = radiant.deep_copy(merchant_data)
               local key = category .. '.' .. merchant
               copied_merchant_data.category = category
               copied_merchant_data.key = key
               if radiant.util.is_string(merchant_data.shop) then
                  copied_merchant_data.shop_info = radiant.resources.load_json(merchant_data.shop).shop_info
               end

               copied_merchant_data.min_city_tier = merchant_data.min_city_tier or 1
               copied_merchant_data.min_stall_tier = merchant_data.min_stall_tier or merchant_data.min_city_tier
               copied_merchant_data.weight = merchant_data.weight or 1
               
               if merchant_data.required_stall then
                  copied_merchant_data.is_exclusive = true
                  exclusive_merchants[key] = copied_merchant_data
               else
                  local category_data = category_merchants[category]
                  if not category_data then
                     category_data = {}
                     category_merchants[category] = category_data
                  end
                  category_data[key] = copied_merchant_data
               end

               all_merchants[key] = copied_merchant_data
            end
         end
      end
   end

   self._categories = data.categories
   self._category_merchants = category_merchants
   self._exclusive_merchants = exclusive_merchants
   self._all_merchants = all_merchants
end

function MercantileService:_merchant_allowed_in_biome(merchant_data, biome_uri)
   if merchant_data.forbidden_biome and merchant_data.forbidden_biome[biome_uri] then
      return false
   end
   if merchant_data.only_biome and not merchant_data.only_biome[biome_uri] then
      return false
   end

   return true
end

function MercantileService:_spawn_all_merchants()
   for player_id, controller in pairs(self._sv.players) do
      controller:determine_daily_merchants() -- checks existing cooldowns when determining which merchants to use
      controller:reduce_merchant_cooldowns() -- then reduces the cooldowns... this way a cooldown of 1 actually means something
   end
end

return MercantileService
