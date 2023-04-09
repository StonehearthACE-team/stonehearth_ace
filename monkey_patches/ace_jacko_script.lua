local AceSpawnJackoScript = class()

function AceSpawnJackoScript:restore()
   self._is_restore = true
end

function AceSpawnJackoScript:post_activate()
   if self._is_restore then
      if self._sv.is_leaving then
         self:_despawn()
      else
         self:_set_combat_listener()
      end
   end
end

return AceSpawnJackoScript
