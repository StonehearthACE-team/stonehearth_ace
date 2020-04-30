local bindings = _radiant.client.get_binding_system()

local AceEntityOrLocationSelector = class()

function AceEntityOrLocationSelector:set_recheck_filter_on_rotation(reconsider)
   self._recheck_filter_on_rotation = reconsider
   return self
end

-- handles keyboard events from the input service
-- Use comma and period to rotate the item
function AceEntityOrLocationSelector:_on_keyboard_event(e)
   local event_consumed = false
   local deltaRot = 0

   -- period and comma rotate the cursor
   if not self._rotation_disabled then
      if bindings:is_action_active('build:rotate:left') then
         deltaRot = 90
      elseif bindings:is_action_active('build:rotate:right') then
         deltaRot = -90
      end

      if deltaRot ~= 0 then
         local new_rotation = (self._rotation + deltaRot) % 360
         self:set_rotation(new_rotation)
         event_consumed = true
         if self._recheck_filter_on_rotation then
            self:_on_mouse_event(_radiant.client.get_mouse_position())
         end
      end
   end

   return event_consumed
end

return AceEntityOrLocationSelector
