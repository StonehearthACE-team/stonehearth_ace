local AcePeriodicAttributeModificationBuff = class()

function AcePeriodicAttributeModificationBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
	local attribute = nil
   self._tuning = json.script_info
	self._pulse_listener = nil
   assert(self._tuning.attribute)

   if not self._tuning or not self._tuning.value_change then
      return
   end
   local pulse_duration = self._tuning.pulse or "15m"
   self._entity = entity
	
	local resources = self._entity:get_component('stonehearth:expendable_resources')
   if resources then
		attribute = resources:get_value(self._tuning.attribute) or nil
   else
		return
   end
	
	if attribute then
		self._pulse_listener = stonehearth.calendar:set_interval("Aura Buff "..buff:get_uri().." pulse", pulse_duration, 
				function()
					self:_on_pulse()
				end)
		if self._tuning.pulse_immediately then
			self:_on_pulse()
		end
	end
end

function AcePeriodicAttributeModificationBuff:on_buff_removed(entity, buff)
   if self._pulse_listener then
      self._pulse_listener:destroy()
      self._pulse_listener = nil
   end
   if self._tuning.pulse_on_destroy and attribute then
      self:_on_pulse()
   end
end

return AcePeriodicAttributeModificationBuff
