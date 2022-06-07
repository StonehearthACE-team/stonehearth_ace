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
      -- generated each morning based on settings/conditions at that time
      self._sv._merchants_to_spawn = {} -- keyed by player id, value is list of merchants to spawn for that town

      -- merchant entities will spawn regardless of whether they get attached to a stall
      -- merchant entities will have a merchant component modeled after shop component
      self._sv._merchants_to_towns = {} -- keyed by merchant id, value is corresponding town controller

      self._sv._initialized = true
   end

   self._morning_spawn_alarm = stonehearth.calendar:set_alarm('8:00', function()
         self:_spawn_all_merchants()
      end)
   
   self:_setup_spawn_timers()
end

function MercantileService:_setup_spawn_timers()
   self._spawning_timers = {}
   for player_id, num_to_spawn in pairs(self._sv._merchants_to_spawn) do
      if num_to_spawn > 0 then
         local town = stonehearth.town:get_town(player_id)
         self._spawning_timers[player_id] = self:_spawn_merchants(town, num_to_spawn)
      end
   end
end

function MercantileService:_spawn_merchants(town, merchants_to_spawn)
   local player_id = town:get_player_id()
   self._sv._merchants_to_spawn[player_id] = merchants_to_spawn
   return stonehearth.calendar:set_interval('towns traveler spawner', '5m+20m', function()
         local traveler = town:spawn_traveler()
         if not self._sv._seen_bulletin[player_id] then
            stonehearth.bulletin_board:post_bulletin(player_id)
               :set_ui_view('StonehearthGenericBulletinDialog')
               :set_callback_instance(self)
               :set_data({
                  title = 'i18n(stonehearth:ui.game.bulletin.traveler.first.title)',
                  message = 'i18n(stonehearth:ui.game.bulletin.traveler.first.message)',
                  zoom_to_entity = traveler,
                  ok_callback = '_on_bulletin_ok',
               })
               :add_i18n_data('traveler_name', radiant.entities.get_custom_name(traveler))
            self._sv._seen_bulletin[player_id] = true
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

function MercantileService:_spawn_all_merchants()
   for player_id, town in pairs(self._sv._target_players) do
      if not self._spawning_timers[player_id] and stonehearth.presence:is_player_connected(player_id) then
         local pop = stonehearth.population:get_population(player_id)
         if pop:get_city_tier() >= stonehearth.constants.merchant.MIN_CITY_TIER then
            local merchants_to_spawn = town:get_merchants_to_spawn()
            if merchants_to_spawn and next(merchants_to_spawn) then
               self._spawning_timers[player_id] = self:_spawn_merchants(town, merchants_to_spawn)
            end
         end
      end
   end
end

return MercantileService
