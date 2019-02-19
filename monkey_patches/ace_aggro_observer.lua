local AceAggroObserver = class()

function AceAggroObserver:reconsider_all_targets()
   self:_remove_all_entities_traces()
   if self._sensor_trace then
      self._target_table:clear()
      self._sensor_trace:push_object_state()
   end
end

return AceAggroObserver