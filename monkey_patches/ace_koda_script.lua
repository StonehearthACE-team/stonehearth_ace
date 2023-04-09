local AceSpawnKodaScript = class()

function AceSpawnKodaScript:restore()
   self._is_restore = true
end

function AceSpawnKodaScript:post_activate()
   if self._is_restore then
      if self._sv.is_leaving then
         self:_despawn()
      else
         self:_set_conversation_listener()
      end
   end
end

return AceSpawnKodaScript
