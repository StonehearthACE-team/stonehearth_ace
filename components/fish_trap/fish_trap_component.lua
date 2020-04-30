--[[
   this is a server and client component
   additionally, it's found on the ghost entity for rendering purposes,
   so functionality should be avoided if "stonehearth:ghost_form" component is present
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
            end
         end)
         :push_object_state()
   end
end

function FishTrapComponent:destroy()
   self:_destroy_listeners()

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
end

function FishTrapComponent:_destroy_parent_listener()
   if self._parent_listener then
      self._parent_listener:destroy()
      self._parent_listener = nil
   end
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

      return self._sv.water_region:get_area() / num_intersect
   end

   return 0
end

function FishTrapComponent:trace(reason)
   return self.__saved_variables:trace(reason)
end

return FishTrapComponent