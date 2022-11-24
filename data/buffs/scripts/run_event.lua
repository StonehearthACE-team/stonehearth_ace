local RunEvent = class()

function RunEvent:on_buff_added(entity, buff)
   self._script_info = buff:get_json().script_info
   self._entity = entity
   self._buff = buff
   self._source = self:_get_source(self._script_info.source)

   if self._script_info.tick then
      local tick_duration = self._script_info.tick
      if self._tick_listener then
         self:_on_tick()
      else
         self._tick_listener = stonehearth.calendar:set_interval("Run Event "..buff:get_uri().." tick", tick_duration, 
            function()
               self:_on_tick()
            end)
      end
   end

   if self._script_info.event and self._script_info.on_added then
      radiant.events.trigger(self._source, tostring(self._script_info.event))
   end
end

function RunEvent:_get_source(source)
   -- try to resolve the source globally; e.g., 'stonehearth' or 'stonehearth_ace.mercantile'
   -- defaults to 'radiant'
   local default = radiant
   local fn = string.format('return function() return %s end', source)
   local f, error = loadstring(fn)
   if f == nil then
      -- parse error?  no problem!
      return default
   end

   local success, result = pcall(function()
         local fetch = f()
         return fetch()
      end)
   if not success then
      return default
   end

   return result
end

function RunEvent:_on_tick()
   if self._script_info.event and self._script_info.tick then
      radiant.events.trigger(self._source, tostring(self._script_info.event))
   end
end

function RunEvent:on_buff_removed(entity, buff)
   if self._tick_listener then
      self._tick_listener:destroy()
      self._tick_listener = nil
   end

   if self._script_info.event and self._script_info.on_removed then
      radiant.events.trigger(self._source, tostring(self._script_info.event))
   end
end

return RunEvent
