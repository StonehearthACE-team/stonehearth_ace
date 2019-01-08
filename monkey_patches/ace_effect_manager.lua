local AceEffectManager = class()

function AceEffectManager:get_resolved_action(action)
   if self._posture_component then
      local postures = self._posture_component:get_postures()
      action = self:_get_posture_mapped_action(action, self._postures, postures)
   end

   if self._happiness_component then
      local mood = self._happiness_component:get_animation_mood()
      action = self:_get_mapped_action(action, self._moods, mood)
   end

   return action
end

function AceEffectManager:_get_posture_mapped_action(action, map, postures)
   -- we'll be passing in a copy of the posture list so it doesn't matter if we modify it
   if not next(postures) then
      table.insert(postures, 1, 'default')
   end

   -- get the map for the posture / mood
   for i = #postures, 1, -1 do
      local posture = postures[i]
      local action_map = map and map[posture]
      -- get the mapped action
      local resolved_action = action_map and action_map[action]

      if resolved_action then
         return resolved_action
      end
   end
   
   return action
end

return AceEffectManager;