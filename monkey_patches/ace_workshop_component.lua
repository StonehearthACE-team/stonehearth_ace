local WorkshopComponent = radiant.mods.require('stonehearth.components.workshop.workshop_component')
local AceWorkshopComponent = class()

-- Create a progress item that tracks the progress of the order item being crafted
function AceWorkshopComponent:start_crafting_progress(order, crafter)
   if order and not self._sv.crafting_progress then
      self._sv.crafting_progress = radiant.create_controller('stonehearth:crafting_progress', order, crafter)
      self._sv.order = order
      self._sv.crafter = crafter
      self.__saved_variables:mark_changed()

      stonehearth.ai:reconsider_entity(self._entity, 'started crafting progress')
   end

   return self._sv.crafting_progress
end

function AceWorkshopComponent:finish_crafting_progress()
   self:_destroy_crafting_progress()
   self._sv.order = nil
   self._sv.crafter = nil
end

-- TODO: use this when crafter dies or is demoted, or order is cancelled
function AceWorkshopComponent:cancel_crafting_progress()
   self:_redistribute_ingredients()
   self:finish_crafting_progress()
end

function AceWorkshopComponent:available_for_work(crafter)
   if not self._sv.crafting_progress then
      return true
   end

   -- if we already have a crafter working here and it's not this crafter, it's not available
   if self._sv.crafter and self._sv.crafter:get_id() ~= crafter:get_id() then
      return false
   end

   local crafter_component = crafter:get_component('stonehearth:crafter')
   if crafter_component then
      local order = crafter_component:get_current_order()
      if order and order:get_id() == self._sv.order:get_id() then
         return true
      end
   end

   return false
end

return AceWorkshopComponent
