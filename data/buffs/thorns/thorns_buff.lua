local ThornsScript = class()

function ThornsScript:on_buff_added(entity, buff)
   if entity and entity:is_valid() then
      self._buff_json = buff._json
	  self._tuning = buff:get_json().script_info
      self._battery_listener = radiant.events.listen(entity, 'stonehearth:combat:battery', self, self._on_hit_received)
   end
end

-- I'm not sure if this would ever get called, but just in case
function ThornsScript:on_buff_removed()
   if self._battery_listener then
      self._battery_listener:destroy()
      self._battery_listener = nil
   end
end

function ThornsScript:_on_hit_received(context)
   -- deal damage to the attacker, percentage based and/or flat amount  
   if context.attacker and context.damage and context.is_melee then
		radiant.entities.modify_health(context.attacker, -1 * (context.damage * (self._tuning.damage_percent or 0) + (self._tuning.flat_damage or 0)))
   end
   
end

return ThornsScript