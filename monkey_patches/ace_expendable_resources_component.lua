local AceExpendableResourcesComponent = class()

function AceExpendableResourcesComponent:set_value(resource_name, value, source)
   if radiant.entities.is_entity_suspended(self._entity) then
      return false
   end

   local min = self:_get_and_update_min_value(resource_name)
   local max = self:_get_and_update_max_value(resource_name)
   local old_value = self._resources[resource_name]
   local new_value = value

   if min then
      new_value = math.max(new_value, min)
   end

   if max then
      new_value = math.min(new_value, max)
   end

   if old_value == new_value then
      return false
   end

   local percentage = self:_calculate_percentage(new_value, max)

   self._resources[resource_name] = new_value
   self._resource_percentages[resource_name] = percentage

   self:_trigger_resource_changed_events(resource_name, source)
   self.__saved_variables:mark_changed()
   return true
end

-- returns the new value
function AceExpendableResourcesComponent:modify_value(resource_name, change, source)
   if radiant.entities.is_entity_suspended(self._entity) then
      return nil
   end

   -- Do we still need this statement?
   -- The caller should have checked to see if the entity is valid
   if not self._resource_data then
      -- If there is no resource tuning, then we are probably a destroyed component!
      return nil
   end

   local old_value = self._resources[resource_name]
   if not old_value then
      return nil
   end

   local new_value = old_value + change
   self:set_value(resource_name, new_value, source)

   return self:get_value(resource_name)
end

function AceExpendableResourcesComponent:_trigger_resource_changed_events(resource_name, source)
   radiant.events.trigger_async(self._entity, 'stonehearth:expendable_resource_changed:' .. resource_name, {
         name = resource_name,
         entity = self._entity,
         source = source
      })
end

return AceExpendableResourcesComponent
