local AceFollowCameraController = class()

function AceFollowCameraController:reinitialize()
   self._orientation = stonehearth.camera:get_orientation()
   self._position = stonehearth.camera:get_position()
   self:__user_initialize()   -- changed from self:initialize() so it doesn't hit the stack overflow flag and cancel out
   self:_enable_listeners()

   local selected = stonehearth.selection:get_selected()

   if selected ~= self._followee then self._should_pop = true end
end

return AceFollowCameraController
