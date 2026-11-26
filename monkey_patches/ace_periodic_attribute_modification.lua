local AcePeriodicAttributeModificationBuff = class()

function AcePeriodicAttributeModificationBuff:_on_pulse()
   local resources = self._entity:is_valid() and self._entity:get_component('stonehearth:expendable_resources')
   if not resources or resources.__destroyed then
      return
   end

   local value_change = self._tuning.value_change
   if self._tuning.is_percentage then
      value_change = resources:get_max_value(self._tuning.attribute) * value_change
   end
   
   local current_value = resources:get_value(self._tuning.attribute)
   local current_guts = resources:get_percentage('guts') or 1
   if current_value <= 0 or current_guts < 1 then
      return  -- don't beat a dead (or incapacitated) horse
   end

   if self._tuning.cannot_reach_zero then
      --if this would reach zero, leave them at a value of 1 instead. "max" and "-" because value_change is negative
      value_change = math.max(value_change, -(current_value - 1))
   end

   radiant.entities.modify_resource(self._entity, self._tuning.attribute, value_change)
end

return AcePeriodicAttributeModificationBuff
