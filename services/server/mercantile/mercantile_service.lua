--[[
   modeled after stonehearth.traveler service:
   - handle the functionality of spawning merchants, bulletins, etc. here,
   - town/population controllers can still contain the factors for how many merchants to spawn
   - merchant stalls register with the town so those factors/capabilities can be computed there
      and easily shown through the town ui (settings will also get saved there)
]]

local MercantileService = class()

function MercantileService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv._initialized then
      self._sv.players = {}

      self._sv._initialized = true
   end

   self:_load_merchant_data()

   self._morning_spawn_alarm = stonehearth.calendar:set_alarm('8:00', function()
         self:_spawn_all_merchants()
      end)
end

function MercantileService:get_player_controller(player_id)
   return self._sv.players[player_id]
end

function MercantileService:add_player_controller(player_id)
   local controller = self:get_player_controller(player_id)
   if not controller then
      controller = radiant.create_controller('stonehearth_ace:player_mercantile_controller', player_id)
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
   return self._category_merchants
end

function MercantileService:get_unique_merchants()
   return self._unique_merchants
end

function MercantileService:get_category_min_city_tier(category)
   local category_data = self._categories[category]
   return category_data and category_data.min_city_tier or 1
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

function MercantileService:_load_merchant_data()
   -- deep copy the loaded table because we're going to be modifying it a lot
   local data = radiant.deep_copy(radiant.resources.load_json('stonehearth_ace:data:merchants'))
   local category_merchants = {}
   local unique_merchants = {}

   for merchant, merchant_data in pairs(data.merchants) do
      merchant_data.key = merchant
      if radiant.util.is_string(merchant_data.shop) then
         merchant_data.shop = radiant.resources.load_json(merchant_data.shop)
      end
      
      if merchant_data.category and data.categories[merchant_data.category] then
         local category_data = category_merchants[merchant_data.category]
         if not category_data then
            category_data = {}
            category_merchants[merchant_data.category] = category_data
         end
         category_data[merchant] = merchant_data
      elseif merchant_data.required_stall then
         unique_merchants[merchant] = merchant_data
      end
   end

   self._category_merchants = category_merchants
   self._unique_merchants = unique_merchants
   self._categories = data.categories
end

function MercantileService:_spawn_all_merchants()
   for player_id, controller in pairs(self._sv.players) do
      controller:create_spawn_timer()
   end
end

return MercantileService
