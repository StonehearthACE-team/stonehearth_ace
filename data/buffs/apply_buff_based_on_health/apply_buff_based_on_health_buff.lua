local ApplyBuffBasedOnHealthScript = class()

function ApplyBuffBasedOnHealthScript:on_buff_added(entity, buff)
   if entity and entity:is_valid() then
      self._entity = entity
      self._buff_json = buff._json
	   self._tuning = buff:get_json().script_info
      self._health_changed_listener = radiant.events.listen(entity, 'stonehearth:expendable_resource_changed:health', self, self._on_health_changed)
   end
end

-- I'm not sure if this would ever get called, but just in case
function ApplyBuffBasedOnHealthScript:on_buff_removed()
   if self._health_changed_listener then
      self._health_changed_listener:destroy()
      self._health_changed_listener = nil
   end
end

function ApplyBuffBasedOnHealthScript:_on_health_changed()
   if self._tuning.cooldown_buff and radiant.entities.has_buff(self._entity, self._tuning.cooldown_buff) then
      return
   end

   if not self._tuning.reapply and radiant.entities.has_buff(self._entity, self._tuning.buff) then
      return
   end

   local current_health = radiant.entities.get_resource_percentage(self._entity, 'health')

   if current_health and (self._tuning.health_percentage_below and current_health < self._tuning.health_percentage_below) or
         (self._tuning.health_percentage_at_least and current_health >= self._tuning.health_percentage_at_least) then
      local options = radiant.shallow_copy(self._tuning.buff)
      options.source = self._entity
      options.source_player = self._entity:get_player_id()
      radiant.entities.add_buff(self._entity, options)
   end
end

return ApplyBuffBasedOnHealthScript