--[[
   this is a server and client component
   additionally, it's found on the ghost entity for rendering purposes,
   so functionality should be avoided if "stonehearth:ghost_form" component is present

   persistent timer for spawning fish to maybe get trapped

   several different states:
      - normal, waiting for fish to be trapped
      - trap triggered, waiting for trapper to come collect (if something trapped) and reset the trap
      - trap triggered, waiting for trapper to come transform it into a trapped fish entity (if something trapped) and reset the trap
]]

local water_lib = require 'stonehearth_ace.lib.water.water_lib'

local FishTrapComponent = class()

function FishTrapComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._square_radius = self._json.square_radius or 5
end

function FishTrapComponent:post_activate()
   if radiant.is_server then
      self._parent_listener = self._entity:add_component('mob'):trace_parent('fish trap placed')
         :on_changed(function(parent)
            if parent then
               self:_destroy_parent_listener()
               self:recheck_water_entity()

               if not self._entity:get_component('stonehearth:ghost_form') then
                  self:_perform_server_non_ghost_setup()
               end
            end
         end)
         :push_object_state()
   end
end

function FishTrapComponent:_perform_server_non_ghost_setup()
   local biome = stonehearth.world_generation:get_biome_alias()
   local settings = radiant.shallow_copy(self._json)
   
   if biome and settings.biomes and settings.biomes[biome] then
      radiant.util.merge_into_table(settings, settings.biomes[biome])
   end
   self._biome_settings = settings
   
   self._season_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
         self:_update_settings_for_season()
      end)
   self:_update_settings_for_season()

   self:_ensure_trap_timer()
end

function FishTrapComponent:_update_settings_for_season()
   local season = stonehearth.seasons:get_current_season() or {}
   local settings = radiant.shallow_copy(self._biome_settings)
   
   if season and season.id and settings.seasons and settings.seasons[season.id] then
      radiant.util.merge_into_table(settings, settings.seasons[season.id])
   end
   self._settings = settings

   self._min_effective_volume = settings.min_effective_water_volume or stonehearth.constants.trapping.fish_traps.MIN_EFFECTIVE_WATER_VOLUME
end

function FishTrapComponent:destroy()
   self:_destroy_listeners()
   self:_destroy_trap_timer()

   if radiant.is_server then
      if self._sv.water_entity and self._sv.water_entity:is_valid() then
         local entity_id = self._entity:get_id()
         local water_id = self._sv.water_entity:get_id()
         stonehearth.trapping:unregister_fish_trap(entity_id, water_id)
         stonehearth_ace.water_signal:unregister_water_change_listener(entity_id, water_id)
      end
   end
end

function FishTrapComponent:_destroy_listeners()
   self:_destroy_parent_listener()
   self:_destroy_season_listener()
end

function FishTrapComponent:_destroy_parent_listener()
   if self._parent_listener then
      self._parent_listener:destroy()
      self._parent_listener = nil
   end
end

function FishTrapComponent:_destroy_season_listener()
   if self._season_listener then
      self._season_listener:destroy()
      self._season_listener = nil
   end
end

function FishTrapComponent:_ensure_trap_timer()
   if not self._sv.trap_tripped and self:_get_effective_volume() > self._min_effective_volume then
      if not self._sv._trap_timer and self._settings.trap_timer then
         self._sv._trap_timer = stonehearth.calendar:set_persistent_timer('fish_trap trip timer', self._settings.trap_timer, radiant.bind(self, '_trip_trap'))
      end
   else
      self:_destroy_trap_timer()
   end
end

function FishTrapComponent:_destroy_trap_timer()
   if self._sv._trap_timer then
      if self._sv._trap_timer.destroy then
         self._sv._trap_timer:destroy()
      end
      self._sv._trap_timer = nil
   end
end

function FishTrapComponent:_trip_trap()
   self:_destroy_trap_timer()

   if self._settings.trap_tripped_effect then
      radiant.effects.run(self._settings.trap_tripped_effect)
   end
   self._sv.trap_tripped = true
   self.__saved_variables:mark_changed()
end

function FishTrapComponent:recheck_water_entity()
   local water, origin = water_lib.get_water_in_front_of_entity(self._entity)
   self:set_water_entity(water, origin)
end

function FishTrapComponent:set_water_entity(water, origin)
   local water_id = water and water:get_id()
   local prev_water_id = self._sv.water_entity and self._sv.water_entity:get_id()

   if water_id ~= prev_water_id then
      if radiant.is_server then
         local entity_id = self._entity:get_id()
         
         if prev_water_id then
            stonehearth.trapping:unregister_fish_trap(entity_id, prev_water_id)
         end

         if water then
            stonehearth.trapping:register_fish_trap(self._entity, water)
            stonehearth_ace.water_signal:register_water_change_listener(entity_id, water_id, function()
                  self:_update_water_region()
               end)
         else
            stonehearth_ace.water_signal:unregister_water_change_listener(entity_id, water_id)
         end
      end

      self._sv.water_entity = water
      self._sv.origin = origin
      self:_update_water_region()
   elseif origin ~= self._sv.origin then
      self._sv.origin = origin
      self:_update_water_region()
   end
end

function FishTrapComponent:get_water_region()
   return self._sv.water_region
end

function FishTrapComponent:_update_water_region()
   if self._sv.water_entity then
      self._sv.water_region = water_lib.get_contiguous_water_subregion(self._sv.water_entity, self._sv.origin, self._square_radius)
   else
      self._sv.water_region = nil
   end
   self.__saved_variables:mark_changed()
end

function FishTrapComponent:_get_effective_volume()
   if self._sv.water_region then
      local volume = self._sv.water_region:get_area()
      local min_effective_volume = self._min_effective_volume
      if volume < min_effective_volume then
         return nil
      end

      -- determine how many traps have their region intersect with this one
      local traps = stonehearth.trapping:get_fish_traps_in_water(self._sv.water_entity:get_id())
      local num_intersect = 1   -- of course there should always be at least 1: this one!
      local entity_id = self._entity:get_id()
      
      for id, trap in pairs(traps) do
         if id ~= entity_id and not trap:get_component('stonehearth:ghost_form') then
            local region = trap:get_component('stonehearth_ace:fish_trap'):get_water_region()
            if region and region:intersects_region(self._sv.water_region) then
               num_intersect = num_intersect + 1
            end
         end
      end

      return volume / num_intersect
   end

   return nil
end

function FishTrapComponent:trace(reason)
   return self.__saved_variables:trace(reason)
end

function FishTrapComponent:is_capture_enabled()
   return self._sv._is_capture_enabled
end

function FishTrapComponent:set_capture_enabled(enabled)
   self._sv._is_capture_enabled = enabled
end



return FishTrapComponent