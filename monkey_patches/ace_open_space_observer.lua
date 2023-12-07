local RaycastLib = require 'stonehearth.ai.lib.raycast_lib'

local OpenSpaceObserver = require 'stonehearth.ai.observers.open_space_observer'
local AceOpenSpaceObserver = class()

AceOpenSpaceObserver._ace_old_post_activate = OpenSpaceObserver.post_activate
function AceOpenSpaceObserver:post_activate()
   local traits_component = self._sv._entity:get_component('stonehearth:traits')
   local prefers_mines = traits_component and traits_component:has_trait('stonehearth_ace:traits:close_mineded')
   is_agoraphobic = traits_component and traits_component:has_trait('stonehearth_ace:traits:agoraphobic')

   if prefers_mines or is_agoraphobic then
      local sampling_period = stonehearth.constants.negative_space.SAMPLING_PERIOD
      self._timer = stonehearth.calendar:set_interval('negative space observer', sampling_period, function()
            self:_update_negative(is_agoraphobic)
         end)

      if self._add_default_thought then
         self:_update_negative(is_agoraphobic)
      end
   else
      self:_ace_old_post_activate()
   end
end

function AceOpenSpaceObserver:_update_negative(is_agoraphobic)
   local entity = self._sv._entity
   local location = radiant.entities.get_world_grid_location(entity)
   local raycast_offset = RaycastLib.get_raycast_offset(entity)
   local thought = 'stonehearth:thoughts:negative_space:outside'

   -- dwarves prefer being in a mined area over being anywhere else
   if stonehearth.mining:get_mined_region():contains(raycast_offset) then
      thought = 'stonehearth:thoughts:negative_space:underground'
   elseif stonehearth.terrain:is_inside_building(location) then
      thought = 'stonehearth:thoughts:negative_space:inside'
   elseif is_agoraphobic then
      thought = 'stonehearth:thoughts:negative_space:agoraphobic'
   end

   radiant.entities.add_thought(entity, thought)
end

return AceOpenSpaceObserver
