-- Health modification generic class
--
local AcePeriodicHealthModificationBuff = class()

function AcePeriodicHealthModificationBuff:_on_pulse()
   local resources = self._entity:is_valid() and self._entity:get_component('stonehearth:expendable_resources')
   if not resources or resources.__destroyed then
      return
   end

   local health_change = self._tuning.health_change
   local min_health = self._tuning.min_health or 0
   if self._tuning.is_percentage then
      local max_health = resources:get_max_value('health')
      health_change = max_health * health_change
      min_health = max_health * min_health
   end
	if self._tuning.buff_modifiers then
		for buff, data in pairs(self._tuning.buff_modifiers) do
			if radiant.entities.has_buff(self._entity, buff) then
				if data.min_health and data.min_health.multiply then
					min_health = min_health * data.min_health.multiply
				elseif data.min_health and data.min_health.add then
					min_health = min_health + data.min_health.add
				end
				if data.health_change and data.health_change.multiply then
					health_change = health_change * data.health_change.multiply
				elseif data.health_change and data.health_change.add then
					health_change = health_change + data.health_change.add
				end
			end
		end
	end

   if self._tuning.multiply_per_axis_buff then
      local axis_buffs = self._entity:get_component('stonehearth:buffs'):get_buffs_by_axis(self._tuning.multiply_per_axis_buff)
      if axis_buffs then
         local multiplier = 0
         for buff, data in pairs(axis_buffs) do
            multiplier = multiplier + 1
		   end

         if multiplier ~= 0 then
            health_change = health_change * multiplier
         end
      end
   end
   
   local current_health = resources:get_value('health')
   local current_guts = resources:get_percentage('guts') or 1
   if current_health <= min_health or current_guts < 1 then
      return  -- don't beat a dead (or incapacitated) horse
   end

   if self._tuning.cannot_kill then
      --if this would kill, leave them at 1 hp instead. "max" and "-" because health_change is negative
      min_health = math.max(min_health, 1)
   end

   health_change = math.max(health_change, -(current_health - min_health))

   radiant.entities.modify_health(self._entity, health_change)
end

return AcePeriodicHealthModificationBuff
