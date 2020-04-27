local WorkshopComponent = radiant.mods.require('stonehearth.components.workshop.workshop_component')
local AceWorkshopComponent = class()

AceWorkshopComponent._ace_old_activate = WorkshopComponent.activate -- doesn't exist!
function AceWorkshopComponent:activate()
   local json = radiant.entities.get_json(self) or {}
   if not self._sv.crafting_time_modifier then
      self._sv.crafting_time_modifier = json.crafting_time_modifier
   end
   
   self._fuel_settings = json.fuel_settings or {}
   if self:uses_fuel() and not self._sv._reserved_fuel then
      self._sv._reserved_fuel = {}
   end
   self:_run_fuel_effect()

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

AceWorkshopComponent._ace_old_destroy = WorkshopComponent.destroy
function AceWorkshopComponent:destroy()
   if self:uses_fuel() then
      self:_unreserve_all_fuel()
   end
   self:_destroy_fuel_effect()
   self:_ace_old_destroy()
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
         return true
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

function AceWorkshopComponent:reserve_fuel(crafter)
   local reserved = self._sv._reserved_fuel
   if reserved[crafter] then
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
      reserved[crafter] = fuel_per_craft

      return true
   end

   -- if that fails, check if there's fuel in storage that can be reserved (just grab the first item; assume the filter works)
   local storage = self._entity:get_component('stonehearth:storage')
   local item_id = next(storage:get_items())
   if item_id then
      local item = storage:remove_item(item_id)
      --radiant.terrain.remove_entity(item)
      
      self:_reserve_crafter_fuel_workshop(crafter)
      reserved[crafter] = item
      
      return true
   end
end

-- if the crafter pre-reserved fuel in a different workshop, free up that fuel before finalizing this fuel reservation
function AceWorkshopComponent:_reserve_crafter_fuel_workshop(crafter)
   local crafter_comp = crafter and crafter:get_component('stonehearth:crafter')
   if crafter_comp then
      local workshop = crafter_comp:get_fuel_reserved_workshop()
      local workshop_comp = workshop and workshop:get_component('stonehearth:workshop')
      if workshop_comp then
         workshop_comp:unreserve_fuel(crafter)
      end

      crafter_comp:set_fuel_reserved_workshop(self._entity)
   end
end

function AceWorkshopComponent:_clear_crafter_fuel_workshop(crafter)
   local crafter_comp = crafter and crafter:get_component('stonehearth:crafter')
   if crafter_comp then
      crafter_comp:set_fuel_reserved_workshop()
   end
end

function AceWorkshopComponent:unreserve_fuel(crafter)
   local fuel = self._sv._reserved_fuel[crafter]
   if fuel then
      if type(fuel) == 'number' then
         local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
         expendable_resources:modify_value('reserved_fuel_level', -fuel)
         expendable_resources:modify_value('fuel_level', fuel)
      else
         -- it's a fuel entity; shove it back in storage, even if there's no room there
         local storage = self._entity:get_component('stonehearth:storage')
         if storage then
            storage:add_item(fuel, true)
         else
            -- if storage got destroyed before we did, dump it on the ground
            local entity = entity_forms_lib.get_in_world_form(self._entity) or self._entity
            local location = radiant.entities.get_world_grid_location(entity)
            if not location then
               local player_id = radiant.entities.get_player_id(entity)
               local town = stonehearth.town:get_town(player_id)
               location = town:get_landing_location()
            end
            radiant.terrain.place_entity(fuel, radiant.terrain.find_placement_point(location, 1, 4))
         end
      end

      self:_clear_crafter_fuel_workshop(crafter)
      
      self._sv._reserved_fuel[crafter] = nil
   end
end

function AceWorkshopComponent:_unreserve_all_fuel()
   for crafter, _ in pairs(self._sv._reserved_fuel) do
      self:unreserve_fuel(crafter)
   end
end

function AceWorkshopComponent:consume_fuel(crafter)
   -- get whatever fuel the crafter has reserved and consume it
   local fuel = self._sv._reserved_fuel[crafter]
   if fuel then
      local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
      if type(fuel) == 'number' and expendable_resources then
         expendable_resources:modify_value('reserved_fuel_level', -fuel)
      else
         local fuel_data = radiant.entities.get_entity_data(fuel, 'stonehearth_ace:fuel') or {}
         -- assume that any individual fuel entity provides at least the amount necessary for one craft
         radiant.entities.destroy_entity(fuel)

         if expendable_resources then
            local fuel_per_craft = self:get_fuel_per_craft()
            local fuel_amount = math.max(fuel_per_craft, fuel_data.fuel_amount or 1) - fuel_per_craft
            if fuel_amount > 0 then
               expendable_resources:modify_value('fuel_level', fuel_amount)
            end
         end
      end

      self:_run_fuel_effect()
      self:_clear_crafter_fuel_workshop(crafter)

      self._sv._reserved_fuel[crafter] = nil
   end
end

function WorkshopComponent:_run_fuel_effect()
   local effect = self:get_fuel_effect()
   if effect and not self._fuel_effect then
      local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
      if expendable_resources then
         local fuel_level = (expendable_resources:get_value('fuel_level') or 0) + (expendable_resources:get_value('reserved_fuel_level') or 0)
         if fuel_level > 0 and not self._fuel_effect then
            self._fuel_effect = radiant.effects.run_effect(self._entity, effect)
            self._fuel_effect:set_finished_cb(function()
                  self:_destroy_fuel_effect()
                  self:_run_fuel_effect()
               end)
         else
            self:_destroy_fuel_effect()
         end
      end
   end
end

function WorkshopComponent:_destroy_fuel_effect()
   if self._fuel_effect then
      self._fuel_effect:set_finished_cb(nil)
                  :stop()
      self._fuel_effect = nil
   end
end

return AceWorkshopComponent
