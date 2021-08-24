local WorkshopComponent = radiant.mods.require('stonehearth.components.workshop.workshop_component')
local AceWorkshopComponent = class()

local log = radiant.log.create_logger('workshop')

AceWorkshopComponent._ace_old_restore = WorkshopComponent.restore -- this should be getting run in activate
function AceWorkshopComponent:restore()
   self._is_restore = true
end

AceWorkshopComponent._ace_old_activate = WorkshopComponent.activate -- doesn't exist!
function AceWorkshopComponent:activate()
   -- this needs to get done after inventory controllers have their restore run; so do it now
   if self._is_restore then
      self:_ace_old_restore()
   end
   
   local json = radiant.entities.get_json(self) or {}
   if not self._sv.crafting_time_modifier then
      self._sv.crafting_time_modifier = json.crafting_time_modifier
      self.__saved_variables:mark_changed()
   end

   self._consumer_component = self._entity:get_component('stonehearth_ace:consumer')

   if self._ace_old_activate then
      self:_ace_old_activate()
   end
end

function AceWorkshopComponent:set_crafting_time_modifier(modifier)
   self._sv.crafting_time_modifier = modifier
end

function AceWorkshopComponent:get_crafting_time_modifier()
   return self._sv.crafting_time_modifier or 1
end

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
   if self._consumer_component then
      self._consumer_component:unreserve_fuel(self._sv.crafter)
   end
   self._sv.order = nil
   self._sv.crafter = nil
end

-- TODO: use this when crafter dies or is demoted, or order is cancelled
function AceWorkshopComponent:cancel_crafting_progress()
   self:_redistribute_ingredients()
   self:finish_crafting_progress()
end

function AceWorkshopComponent:_redistribute_ingredients()
   local location = radiant.entities.get_world_grid_location(self._entity)
   local ec_children = {}
   local entity_container = self._entity:get_component('entity_container')
   if entity_container then
      for id, child in entity_container:each_child() do
         if child and child:is_valid() then
            ec_children[id] = child
         end
      end

      if next(ec_children) then
         local location = radiant.entities.get_world_grid_location(self._entity)
         local player_id = radiant.entities.get_player_id(self._entity)
         local default_storage
         if not location then
            local town = stonehearth.town:get_town(player_id)
            if town then
               default_storage = town:get_default_storage()
               location = town:get_landing_location()
            end
         end
         local options = {
            inputs = default_storage,
            spill_fail_items = true,
            require_matching_filter_override = true,
         }
         radiant.entities.output_spawned_items(ec_children, location, 1, 4, options)
      end
   end
end

function AceWorkshopComponent:available_for_work(crafter)
   if not self._sv.crafting_progress then
      if not self._consumer_component or self._consumer_component:reserve_fuel(crafter) then
         return true
      end
   end

   -- if we already have a crafter working here and it's not this crafter, it's not available
   if self._sv.crafter and self._sv.crafter:is_valid() and self._sv.crafter:get_id() ~= crafter:get_id() then
      return false
   end

   local crafter_component = crafter:get_component('stonehearth:crafter')
   if crafter_component then
      local order = crafter_component:get_current_order()
      if order and self._sv.order and (order:get_id() == self._sv.order:get_id()) then
         return not self._consumer_component or self._consumer_component:reserve_fuel(crafter)
      end
   end

   return false
end

AceWorkshopComponent._ace_old_run_effect = WorkshopComponent.run_effect
function AceWorkshopComponent:run_effect()
   self:_ace_old_run_effect()
   if self._consumer_component then
      self._consumer_component:set_currently_consuming(true)
   end
end

AceWorkshopComponent._ace_old_stop_running_effect = WorkshopComponent.stop_running_effect
function AceWorkshopComponent:stop_running_effect()
   self:_ace_old_stop_running_effect()
   if self._consumer_component then
      self._consumer_component:set_currently_consuming(false)
   end
end

return AceWorkshopComponent
