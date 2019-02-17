local Entity = _radiant.om.Entity

local Relations = require 'stonehearth.lib.player.relations'
local AceRelations = class()

AceRelations._ace_old_are_entities_hostile = Relations.are_entities_hostile
function AceRelations:are_entities_hostile(player_a, player_b)
   -- check to see if this particular entity B is non-hostile to A
   -- for some reason, B is the thinking entity, A is the target
   if radiant.util.is_a(player_b, Entity) then
      local properties_comp = player_b:get_component('stonehearth:properties')
      local avoid_hunting = properties_comp and properties_comp:has_property('avoid_hunting')
      if avoid_hunting and radiant.entities.get_player_id(player_a) == 'animals' then
         return false
      end
   end
   
   return self:_ace_old_are_entities_hostile(player_a, player_b)
end

return AceRelations