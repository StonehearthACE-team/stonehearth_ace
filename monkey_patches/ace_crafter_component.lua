local CrafterComponent = radiant.mods.require('stonehearth.components.crafter.crafter_component')
local log = radiant.log.create_logger('crafter')

local AceCrafterComponent = class()

--If you stop being a crafter, b/c you're killed or demoted,
--drop all your stuff, and release your crafting order, if you have one.
function AceCrafterComponent:clean_up_order()
   self:_distribute_all_crafting_ingredients()
   if self._sv.curr_order then
      self._sv.curr_order:reset_progress(self._entity)   -- Paul: added entity reference for multiple-crafter compatibility
      self._sv.curr_order:set_crafting_status(self._entity, nil)  -- Paul: added entity reference for multiple-crafter compatibility
      self._sv.curr_order = nil
   end
   if self._sv.curr_workshop then
      if self._sv.curr_workshop:is_valid() then
         local workshop_component = self._sv.curr_workshop:get_component('stonehearth:workshop')
         workshop_component:cancel_crafting_progress()
      end
      self._sv.curr_workshop = nil
   end
   self.__saved_variables:mark_changed()
end

return AceCrafterComponent
