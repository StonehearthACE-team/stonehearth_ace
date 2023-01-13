local ApplyBuffBasedOnHealthScript = class()

function ApplyBuffBasedOnHealthScript:on_buff_added(entity, buff)
   if entity and entity:is_valid() then
      self._entity = entity
      self._buff_json = buff._json
	   self._tuning = buff:get_json().script_info
      self._battery_listener = radiant.events.listen(entity, 'stonehearth:combat:battery', self, self._on_hit_received)
   end
end

-- I'm not sure if this would ever get called, but just in case
function ApplyBuffBasedOnHealthScript:on_buff_removed()
   if self._battery_listener then
      self._battery_listener:destroy()
      self._battery_listener = nil
   end
end

function ApplyBuffBasedOnHealthScript:_on_hit_received(context)
   if self._tuning.cooldown_buff and radiant.entities.has_buff(self._entity, self._tuning.cooldown_buff) then
      return
   end

   if not self._tuning.reapply and radiant.entities.has_buff(self._entity, self._tuning.buff) then
      return
   end

   local current_health = radiant.entities.get_resource_percentage(self._entity, 'health')

   if current_health and current_health < self._tuning.health_percentage then
      radiant.entities.add_buff(self._entity, self._tuning.buff)
   end
   
end

return ApplyBuffBasedOnHealthScript