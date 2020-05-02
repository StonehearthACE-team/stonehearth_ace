local constants = require 'stonehearth.constants'

local WorkshopComponent = radiant.mods.require('stonehearth.components.workshop.workshop_component')
local AceWorkshopComponent = class()

local FUEL_LEASE_NAME = constants.ai.RESERVATION_LEASE_NAME
local log = radiant.log.create_logger('workshop')

AceWorkshopComponent._ace_old_activate = WorkshopComponent.activate -- doesn't exist!
function AceWorkshopComponent:activate()
   local json = radiant.entities.get_json(self) or {}
   if not self._sv.crafting_time_modifier then
      self._sv.crafting_time_modifier = json.crafting_time_modifier
   end
   
   self._fuel_settings = json.fuel_settings or {}
   self._reserved_fuel = {}
   self._reserved_fuel_items = {}

   -- if this is an auto-crafter, get rid of the show workshop command
   local crafter_component = self._entity:get_component('stonehearth:crafter')
   if crafter_component and crafter_component:is_auto_crafter() then
      local command_component = self._entity:add_component('stonehearth:commands')
      if command_component then
         command_component:remove_command('stonehearth:commands:show_workshop')
      end
   end

   if self._ace_old_activate then
      self:_ace_old_activate()
   end
end

AceWorkshopComponent._ace_old_post_activate = WorkshopComponent.post_activate -- doesn't exist!
function AceWorkshopComponent:post_activate()
   if self:uses_fuel() then
      local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
      if expendable_resources then
         local fuel_level = expendable_resources:get_value('fuel_level')
         local reserved_fuel_level = expendable_resources:get_value('reserved_fuel_level')
         if fuel_level and reserved_fuel_level then
            expendable_resources:modify_value('fuel_level', reserved_fuel_level)
            expendable_resources:set_value('reserved_fuel_level', 0)
         end
      end

      -- should we also listen for expendable resources changes?
      self._storage_filter_changed_listener = radiant.events.listen(self._entity, 'stonehearth:storage:filter_changed', function(args)
            self:_reconsider_all_item_leases()
         end)
      self._storage_item_added_listener = radiant.events.listen(self._entity, 'stonehearth:storage:item_added', function(args)
            self:_reconsider_item_lease(args.item)
            self:_update_fueled()
         end)
      self._storage_item_removed_listener = radiant.events.listen(self._entity, 'stonehearth:storage:item_removed', function(args)
            if args.item then
               self:_release_item_lease(args.item)
            end
            if self._entity:get_component('stonehearth:storage'):is_empty() then
               self:_update_fueled()
            end
         end)

      self:_reconsider_all_item_leases()
      self:_update_fueled()
   end

   if self._ace_old_post_activate then
      self:_ace_old_post_activate()
   end
end

AceWorkshopComponent._ace_old_destroy = WorkshopComponent.destroy
function AceWorkshopComponent:destroy()
   if self:uses_fuel() then
      self:_unreserve_all_fuel()
   end
   self:_destroy_fuel_effect()
   self:_destroy_no_fuel_effect()
   self:_ace_old_destroy()
end

function AceWorkshopComponent:_destroy_listeners()
   if self._storage_filter_changed_listener then
      self._storage_filter_changed_listener:destroy()
      self._storage_filter_changed_listener = nil
   end
   if self._storage_item_added_listener then
      self._storage_item_added_listener:destroy()
      self._storage_item_added_listener = nil
   end
   if self._storage_item_removed_listener then
      self._storage_item_removed_listener:destroy()
      self._storage_item_removed_listener = nil
   end
end

function AceWorkshopComponent:_reconsider_all_item_leases()
   -- refresh (acquire or release) leases on all items based on the new filter (unless they're already reserved)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      for _, item in pairs(storage:get_items()) do
         self:_reconsider_item_lease(item)
      end
   end
end

function AceWorkshopComponent:_reconsider_item_lease(item)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      if radiant.entities.get_entity_data(item, 'stonehearth_ace:fuel') and (self._reserved_fuel_items[item:get_id()] or storage:passes(item)) then
         self:_acquire_item_lease(item)
      else
         self:_release_item_lease(item)
      end
   end
end

function AceWorkshopComponent:_acquire_item_lease(item)
   local success = radiant.entities.acquire_lease(item, FUEL_LEASE_NAME, self._entity, true) -- , false)
   --log:debug('%s %s acquiring lease for %s', self._entity, success and 'SUCCEEDED' or 'FAILED', item)
end

function AceWorkshopComponent:_release_item_lease(item)
   local success = radiant.entities.release_lease(item, FUEL_LEASE_NAME, self._entity)
   --log:debug('%s %s releasing lease for %s', self._entity, success and 'SUCCEEDED' or 'FAILED', item)
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
   if self:uses_fuel() then
      self:unreserve_fuel(self._sv.crafter)
   end
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
      if not self:uses_fuel() or self:reserve_fuel(crafter) then
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
         return not self:uses_fuel() or self:reserve_fuel(crafter)
      end
   end

   return false
end

function AceWorkshopComponent:uses_fuel()
   return self._fuel_settings.uses_fuel
end

function AceWorkshopComponent:get_fuel_per_craft()
   return self._fuel_settings.fuel_per_craft or 1
end

function AceWorkshopComponent:get_fuel_effect()
   return self._fuel_settings.fuel_effect
end

function AceWorkshopComponent:get_no_fuel_effect()
   return self._fuel_settings.no_fuel_effect
end

function AceWorkshopComponent:get_fueled_buff()
   return self._fuel_settings.fueled_buff
end

function AceWorkshopComponent:get_no_fuel_model_variant()
   return self._fuel_settings.no_fuel_model_variant
end

function AceWorkshopComponent:is_fueled()
   local storage = self._entity:get_component('stonehearth:storage')
   if storage and storage:get_num_items() > 0 then
      return true
   end

   local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
   if expendable_resources then
      return (expendable_resources:get_value('fuel_level') or 0) + (expendable_resources:get_value('reserved_fuel_level') or 0) >= self:get_fuel_per_craft()
   end

   return false
end

function AceWorkshopComponent:reserve_fuel(crafter)
   local reserved = self._reserved_fuel
   local reserved_items = self._reserved_fuel_items

   local crafter_id = crafter:get_id()
   if reserved[crafter_id] then
      return true
   end

   local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
   if not expendable_resources then
      return false
   end
   if not expendable_resources:get_value('fuel_level') or not expendable_resources:get_value('reserved_fuel_level') then
      return false
   end

   local fuel_per_craft = self:get_fuel_per_craft()

   -- first check if we can simply reserve any current fuel
   if expendable_resources:get_value('fuel_level') >= fuel_per_craft then
      expendable_resources:modify_value('fuel_level', -fuel_per_craft)
      expendable_resources:modify_value('reserved_fuel_level', fuel_per_craft)
      
      self:_reserve_crafter_fuel_workshop(crafter)
      reserved[crafter_id] = fuel_per_craft

      return true
   end

   -- if that fails, check if there's fuel in storage that can be reserved (just grab the first item; assume the filter works)
   local storage = self._entity:get_component('stonehearth:storage')
   local items = storage and storage:get_items()
   if items then
      for _, item in pairs(items) do
         local item_id = item:get_id()
         if not reserved_items[item_id] and radiant.entities.get_entity_data(item, 'stonehearth_ace:fuel') then
            self:_reserve_crafter_fuel_workshop(crafter)
            reserved[crafter_id] = item
            reserved_items[item_id] = crafter_id
            
            return true
         end
      end
   end
end

-- if the crafter pre-reserved fuel in a different workshop, free up that fuel before finalizing this fuel reservation
function AceWorkshopComponent:_reserve_crafter_fuel_workshop(crafter)
   local crafter_comp = crafter and crafter:get_component('stonehearth:crafter')
   if crafter_comp then
      local workshop = crafter_comp:get_fuel_reserved_workshop()
      local workshop_comp = workshop and workshop:is_valid() and workshop:get_component('stonehearth:workshop')
      if workshop_comp then
         workshop_comp:unreserve_fuel(crafter)
      end

      crafter_comp:set_fuel_reserved_workshop(self._entity)
   end
end

function AceWorkshopComponent:_clear_crafter_fuel_workshop(crafter_id)
   local crafter = radiant.entities.get_entity(crafter_id)
   local crafter_comp = crafter and crafter:is_valid() and crafter:get_component('stonehearth:crafter')
   if crafter_comp then
      crafter_comp:set_fuel_reserved_workshop()
   end
end

function AceWorkshopComponent:unreserve_fuel(crafter_id)
   local fuel = self._reserved_fuel[crafter_id]
   if fuel then
      if type(fuel) == 'number' then
         local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
         expendable_resources:modify_value('reserved_fuel_level', -fuel)
         expendable_resources:modify_value('fuel_level', fuel)
      else
         -- it's a fuel entity
         self._reserved_fuel_items[fuel:get_id()] = nil
         self:_reconsider_item_lease(fuel)
      end

      self:_clear_crafter_fuel_workshop(crafter_id)
      
      self._reserved_fuel[crafter_id] = nil
   end
end

function AceWorkshopComponent:_unreserve_all_fuel()
   for crafter_id, _ in pairs(self._reserved_fuel) do
      self:unreserve_fuel(crafter_id)
   end
end

function AceWorkshopComponent:consume_fuel(crafter)
   -- get whatever fuel the crafter has reserved and consume it
   local crafter_id = crafter:get_id()
   local fuel = self._reserved_fuel[crafter_id]
   if fuel then
      local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
      if type(fuel) == 'number' then
         if expendable_resources then
            expendable_resources:modify_value('reserved_fuel_level', -fuel)
         end
      else
         -- first check if there's now a high enough fuel level that we can just take from that
         -- instead of consuming the fuel entity
         local fuel_per_craft = self:get_fuel_per_craft()
         local fuel_level = expendable_resources and expendable_resources:get_value('fuel_level') or 0
         if fuel_level >= fuel_per_craft then
            self:unreserve_fuel(crafter_id)
            expendable_resources:modify_value('fuel_level', -fuel_per_craft)
         else
            local fuel_data = radiant.entities.get_entity_data(fuel, 'stonehearth_ace:fuel') or {}
            -- assume that any individual fuel entity provides at least the amount necessary for one craft

            if expendable_resources then
               local fuel_amount = math.max(fuel_per_craft, fuel_data.fuel_amount or 1) - fuel_per_craft
               if fuel_amount > 0 then
                  expendable_resources:modify_value('fuel_level', fuel_amount)
               end
            end

            self._reserved_fuel_items[fuel:get_id()] = nil
            -- probably don't need to release the lease since the entity is just getting destroyed
            -- do we even need to remove it from storage?
            -- radiant.entities.release_lease(fuel, FUEL_LEASE_NAME, self._entity)
            self._entity:get_component('stonehearth:storage'):remove_item(fuel:get_id())
            radiant.entities.destroy_entity(fuel)
         end
      end

      self:_update_fueled()
      self:_clear_crafter_fuel_workshop(crafter_id)

      self._reserved_fuel[crafter_id] = nil
   end
end

AceWorkshopComponent._ace_old_run_effect = WorkshopComponent.run_effect
function AceWorkshopComponent:run_effect()
   self:_ace_old_run_effect()
   self._fueled_while_working = true
   self:_update_fueled()
end

AceWorkshopComponent._ace_old_stop_running_effect = WorkshopComponent.stop_running_effect
function AceWorkshopComponent:stop_running_effect()
   self:_ace_old_stop_running_effect()
   self._fueled_while_working = false
   self:_update_fueled()
end

function AceWorkshopComponent:_update_fueled()
   self:_update_fueled_buff()
   self:_update_fuel_effect()
end

function AceWorkshopComponent:_update_fueled_buff()
   local buff = self:get_fueled_buff()
   if buff then
      if self._fueled_while_working or self:is_fueled() then
         if not radiant.entities.has_buff(self._entity, buff) then
            radiant.entities.add_buff(self._entity, buff)
         end
      else
         radiant.entities.remove_buff(self._entity, buff)
      end
   end
end

function AceWorkshopComponent:_update_fuel_effect()
   if self._effect then
      self:_destroy_fuel_effect()
      self:_destroy_no_fuel_effect()
      self:_reset_fuel_model_variant()
      return
   end
   
   local is_fueled = self:is_fueled()

   if is_fueled then
      self:_destroy_no_fuel_effect()
      self:_reset_fuel_model_variant()

      local effect = self:get_fuel_effect()
      if effect and not self._fuel_effect then
         self._fuel_effect = radiant.effects.run_effect(self._entity, effect)
         self._fuel_effect:set_finished_cb(function()
               self:_destroy_fuel_effect()
               self:_update_fuel_effect()
            end)
      end
   else
      self:_destroy_fuel_effect()
      self:_set_fuel_model_variant()
      
      local effect = self:get_no_fuel_effect()
      if effect and not self._no_fuel_effect then
         self._no_fuel_effect = radiant.effects.run_effect(self._entity, effect)
         self._no_fuel_effect:set_finished_cb(function()
               self:_destroy_no_fuel_effect()
               self:_update_fuel_effect()
            end)
      end
   end
end

function AceWorkshopComponent:_destroy_fuel_effect()
   if self._fuel_effect then
      self._fuel_effect:set_finished_cb(nil)
                  :stop()
      self._fuel_effect = nil
   end
end

function AceWorkshopComponent:_destroy_no_fuel_effect()
   if self._no_fuel_effect then
      self._no_fuel_effect:set_finished_cb(nil)
                  :stop()
      self._no_fuel_effect = nil
   end
end

function AceWorkshopComponent:_reset_fuel_model_variant()
   -- nothing to reset if there is no model variant for no fuel
   local model_variant = self:get_no_fuel_model_variant()
   if model_variant then
      self._entity:add_component('stonehearth_ace:entity_modification'):reset_model_variant()
   end
end

function AceWorkshopComponent:_set_fuel_model_variant()
   local model_variant = self:get_no_fuel_model_variant()
   if model_variant then
      self._entity:add_component('stonehearth_ace:entity_modification'):set_model_variant(model_variant)
   end
end

return AceWorkshopComponent
