local WildernessComponent = class()
local get_world_grid_location = radiant.entities.get_world_grid_location
local get_entities_at_point = radiant.terrain.get_entities_at_point

local wilderness_signal_filter_fn = function(entity)
   return entity:get_component('stonehearth_ace:wilderness_signal') ~= nil
end

function WildernessComponent:create()
   local json = radiant.entities.get_json(self)
   self._sv.wilderness_value = (json and json.wilderness_value) or 0
   self._sv.is_mobile = (json and json.is_mobile) or false
   self._sv._current_signals = {}
   self.__saved_variables:mark_changed()
end

function WildernessComponent:post_activate()
   -- if this entity is mobile, we want to periodically check its location to see if it's within a wilderness signal
   if self._sv.is_mobile == nil then
      -- check if it's an animal
      local catalog_data = get_catalog_data(entity)
      self._sv.is_mobile = (catalog_data and catalog_data.player_id == 'animals') or false
   end
   if not self._sv._current_signals then
      self._sv._current_signals = self._sv.current_signals or {}
   end
   self._sv.current_signals = nil

   if self._sv.is_mobile then
      self._location_check_timer = stonehearth.calendar:set_interval('wilderness mobility check', '9m+2m', function()
         self:_perform_location_check()
      end)
   end
end

function WildernessComponent:destroy()
   if self._location_check_timer then
      self._location_check_timer:destroy()
      self._location_check_timer = nil
   end
end

function WildernessComponent:get_wilderness_value()
   return self._sv.wilderness_value
end

function WildernessComponent:set_wilderness_value(value)
   if value ~= self.sv.wilderness_value then
      self._sv.wilderness_value = value
      self.__saved_variables:mark_changed()
      radiant.events.trigger(self._entity, 'stonehearth_ace:wilderness:wilderness_value_changed', value)
   end
end

function WildernessComponent:_perform_location_check()
   local location = get_world_grid_location(self._entity)
   local signals = location and get_entities_at_point(location, wilderness_signal_filter_fn)

   -- first check our current signals to see if we've left any (or if they no longer exist)
   for id, entity in pairs(self._sv._current_signals) do
      local component = entity:get_component('stonehearth_ace:wilderness_signal')
      if not component then
         self._sv._current_signals[id] = nil
      elseif not location or not signals[id] then  -- if there's no location, it must not be in the world, so remove it from signals
         component:remove_entity(self._entity)
         self._sv._current_signals[id] = nil
      end
   end
   
   if signals then
      -- then check the new ones to see if we've entered any
      for id, entity in pairs(signals) do
         if not self._sv._current_signals[id] then
            self._sv._current_signals[id] = entity
            entity:get_component('stonehearth_ace:wilderness_signal'):add_entity(self._entity)
         end
      end
   end
end

return WildernessComponent
