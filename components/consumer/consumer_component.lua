--[[
   primary usage is consuming fuel for workbenches
   will eventually also be used for fuel-powered producers of mechanical power
]]

local log = radiant.log.create_logger('consumer')

local ConsumerComponent = class()

function ConsumerComponent:activate()
   local json = radiant.entities.get_json(self) or {}

   self._fuel_settings = json.fuel_settings or {}
   self._reserved_fuel = {}
   self._reserved_fuel_items = {}

   -- remote to client for fuel display in stockpile window
   self._sv.fuel_per_use = self:get_fuel_per_use()
   local ui_settings = json.ui_settings
   if ui_settings then
      self._sv.fuel_label = ui_settings.fuel_label
      self._sv.fuel_tooltip = ui_settings.fuel_tooltip
      self._sv.fuel_use_icon = ui_settings.fuel_use_icon
      self._sv.no_fuel_use_icon = ui_settings.no_fuel_use_icon
      self._sv.extra_fuel_use_icon = ui_settings.extra_fuel_use_icon
      self._sv.max_fuel_icons = ui_settings.max_fuel_icons
   end
   self.__saved_variables:mark_changed()
end

function ConsumerComponent:post_activate()
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
         self:_reconsider_all_items()
      end)
   self._storage_item_added_listener = radiant.events.listen(self._entity, 'stonehearth:storage:item_added', function(args)
         self:_update_fueled()
      end)
   self._storage_item_removed_listener = radiant.events.listen(self._entity, 'stonehearth:storage:item_removed', function(args)
         if self._entity:get_component('stonehearth:storage'):is_empty() then
            self:_update_fueled()
         end
      end)

   self:_reconsider_all_items()
   self:_update_fueled()
end

function ConsumerComponent:destroy()
   self:_unreserve_all_fuel()
   self:_destroy_fuel_effect()
   self:_destroy_no_fuel_effect()
end

function ConsumerComponent:_destroy_listeners()
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

function ConsumerComponent:_reconsider_all_items()
   -- reconsider all items based on the new filter (unless they're already reserved)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      local output_items = {}
      for _, item in pairs(storage:get_items()) do
         if item:is_valid() and
               (not radiant.entities.get_entity_data(item, 'stonehearth_ace:fuel') or
               (not self._reserved_fuel_items[item:get_id()] and not storage:passes(item))) then
            -- remove any item that doesn't belong
            local id = item:get_id()
            output_items[id] = item
            storage:remove_item(id)
         end
      end

      -- pop out any removed items
      if next(output_items) then
         log:debug('dumping items from %s: %s', self._entity, radiant.util.table_tostring(output_items))
         
         -- try to place the items right in front of the entity
         local destination = self._entity:get_component('destination')
         local adjacent_region = destination and destination:get_adjacent()
         local adjacent_min = adjacent_region and adjacent_region:get() and not adjacent_region:get():empty() and adjacent_region:get():get_bounds().min
         local location = adjacent_min and radiant.entities.local_to_world(adjacent_min, self._entity) or radiant.entities.get_world_grid_location(self._entity)

         local town = stonehearth.town:get_town(self._entity)
         local default_storage = town and town:get_default_storage()

         radiant.entities.output_spawned_items(output_items, location, 1, 2, nil, nil, default_storage, true)
      end
   end
end

function ConsumerComponent:get_fuel_per_use()
   return self._fuel_settings.fuel_per_use or 1
end

function ConsumerComponent:get_fuel_effect()
   return self._fuel_settings.fuel_effect
end

function ConsumerComponent:get_no_fuel_effect()
   return self._fuel_settings.no_fuel_effect
end

function ConsumerComponent:get_fueled_buff()
   return self._fuel_settings.fueled_buff
end

function ConsumerComponent:get_no_fuel_model_variant()
   return self._fuel_settings.no_fuel_model_variant
end

function ConsumerComponent:is_fueled()
   local storage = self._entity:get_component('stonehearth:storage')
   if storage and storage:get_num_items() > 0 then
      return true
   end

   local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
   if expendable_resources then
      return (expendable_resources:get_value('fuel_level') or 0) + (expendable_resources:get_value('reserved_fuel_level') or 0) >= self:get_fuel_per_use()
   end

   return false
end

function ConsumerComponent:reserve_fuel(user)
   local reserved = self._reserved_fuel
   local reserved_items = self._reserved_fuel_items

   local user_id = user:get_id()
   if reserved[user_id] then
      return true
   end

   local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
   if not expendable_resources then
      return false
   end
   if not expendable_resources:get_value('fuel_level') or not expendable_resources:get_value('reserved_fuel_level') then
      return false
   end

   local fuel_per_use = self:get_fuel_per_use()

   -- first check if we can simply reserve any current fuel
   if expendable_resources:get_value('fuel_level') >= fuel_per_use then
      expendable_resources:modify_value('fuel_level', -fuel_per_use)
      expendable_resources:modify_value('reserved_fuel_level', fuel_per_use)
      
      self:_reserve_user_fuel_consumer(user)
      reserved[user_id] = fuel_per_use

      return true
   end

   -- if that fails, check if there's fuel in storage that can be reserved (just grab the first item; assume the filter works)
   local storage = self._entity:get_component('stonehearth:storage')
   local items = storage and storage:get_items()
   if items then
      for _, item in pairs(items) do
         local item_id = item:get_id()
         if not reserved_items[item_id] and radiant.entities.get_entity_data(item, 'stonehearth_ace:fuel') then
            self:_reserve_user_fuel_consumer(user)
            reserved[user_id] = item
            reserved_items[item_id] = user_id
            
            return true
         end
      end
   end
end

-- if the crafter pre-reserved fuel in a different consumer, free up that fuel before finalizing this fuel reservation
function ConsumerComponent:_reserve_user_fuel_consumer(user)
   local crafter_comp = user and user:get_component('stonehearth:crafter')
   if crafter_comp then
      local consumer = crafter_comp:get_fuel_reserved_consumer()
      local consumer_comp = consumer and consumer:is_valid() and consumer:get_component('stonehearth_ace:consumer')
      if consumer_comp then
         consumer_comp:unreserve_fuel(user)
      end

      crafter_comp:set_fuel_reserved_consumer(self._entity)
   end
end

function ConsumerComponent:_clear_user_fuel_consumer(user_id)
   local user = radiant.entities.get_entity(user_id)
   local crafter_comp = user and user:is_valid() and user:get_component('stonehearth:crafter')
   if crafter_comp then
      crafter_comp:set_fuel_reserved_consumer()
   end
end

function ConsumerComponent:unreserve_fuel(user_id)
   local fuel = self._reserved_fuel[user_id]
   if fuel then
      if type(fuel) == 'number' then
         local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
         expendable_resources:modify_value('reserved_fuel_level', -fuel)
         expendable_resources:modify_value('fuel_level', fuel)
      elseif fuel:is_valid() then
         -- it's a fuel entity
         self._reserved_fuel_items[fuel:get_id()] = nil
      end

      self:_clear_user_fuel_consumer(user_id)
      
      self._reserved_fuel[user_id] = nil
   end
end

function ConsumerComponent:_unreserve_all_fuel()
   for user_id, _ in pairs(self._reserved_fuel) do
      self:unreserve_fuel(user_id)
   end
end

function ConsumerComponent:consume_fuel(user)
   -- get whatever fuel the user has reserved and consume it
   local user_id = user:get_id()
   local fuel = self._reserved_fuel[user_id]
   if fuel then
      local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
      if type(fuel) == 'number' then
         if expendable_resources then
            expendable_resources:modify_value('reserved_fuel_level', -fuel)
         end
      elseif fuel:is_valid() then
         -- first check if there's now a high enough fuel level that we can just take from that
         -- instead of consuming the fuel entity
         local fuel_per_use = self:get_fuel_per_use()
         local fuel_level = expendable_resources and expendable_resources:get_value('fuel_level') or 0
         if fuel_level >= fuel_per_use then
            self:unreserve_fuel(user_id)
            expendable_resources:modify_value('fuel_level', -fuel_per_use)
         else
            local fuel_data = radiant.entities.get_entity_data(fuel, 'stonehearth_ace:fuel') or {}
            -- assume that any individual fuel entity provides at least the amount necessary for one craft

            if expendable_resources then
               local fuel_amount = math.max(fuel_per_use, fuel_data.fuel_amount or 1) - fuel_per_use
               if fuel_amount > 0 then
                  expendable_resources:modify_value('fuel_level', fuel_amount)
               end
            end

            self._reserved_fuel_items[fuel:get_id()] = nil
            -- do we even need to remove it from storage?
            self._entity:get_component('stonehearth:storage'):remove_item(fuel:get_id())
            radiant.entities.destroy_entity(fuel)
         end
      end

      self:_update_fueled()
      self:_clear_user_fuel_consumer(user_id)

      self._reserved_fuel[user_id] = nil
   end
end

function ConsumerComponent:set_currently_consuming(consuming)
   self._currently_consuming = consuming
   self:_update_fueled()
end

function ConsumerComponent:_update_fueled()
   self:_update_fueled_buff()
   self:_update_fuel_effect()
end

function ConsumerComponent:_update_fueled_buff()
   local buff = self:get_fueled_buff()
   if buff then
      if self._currently_consuming or self:is_fueled() then
         if not radiant.entities.has_buff(self._entity, buff) then
            radiant.entities.add_buff(self._entity, buff)
         end
      else
         radiant.entities.remove_buff(self._entity, buff)
      end
   end
end

function ConsumerComponent:_update_fuel_effect()
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

function ConsumerComponent:_destroy_fuel_effect()
   if self._fuel_effect then
      self._fuel_effect:set_finished_cb(nil)
                  :stop()
      self._fuel_effect = nil
   end
end

function ConsumerComponent:_destroy_no_fuel_effect()
   if self._no_fuel_effect then
      self._no_fuel_effect:set_finished_cb(nil)
                  :stop()
      self._no_fuel_effect = nil
   end
end

function ConsumerComponent:_reset_fuel_model_variant()
   -- nothing to reset if there is no model variant for no fuel
   local model_variant = self:get_no_fuel_model_variant()
   if model_variant then
      self._entity:add_component('stonehearth_ace:entity_modification'):reset_model_variant()
   end
end

function ConsumerComponent:_set_fuel_model_variant()
   local model_variant = self:get_no_fuel_model_variant()
   if model_variant then
      self._entity:add_component('stonehearth_ace:entity_modification'):set_model_variant(model_variant)
   end
end

return ConsumerComponent
