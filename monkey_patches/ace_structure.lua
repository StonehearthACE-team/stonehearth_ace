--local Structure = require 'stonehearth.components.building2.structure'
local AceStructure = class()

function AceStructure:_update_score()
   if not radiant.is_server then
      return
   end

   local score = 0

   -- Scaffolding doesn't have a score.
   if self._sv._is_platform then
      return
   end

   local area = self:get_current_shape_region():get_area()
   local score = 0
   if area > 0 then
      -- Only do this if score > 0 because otherwise score is not a number!
      local net_worth = radiant.entities.get_net_worth(self._entity)
      local item_multiplier = net_worth or self:_get_building_quality()
      score = (area * item_multiplier) ^ 0.7

      score = radiant.math.round(score)
   end
   stonehearth.score:change_score(self._entity, 'net_worth', 'buildings', score)
end

function AceStructure:_get_building_quality()
   local building_comp = self._sv._owning_building and self._sv._owning_building:get_component('stonehearth:build2:building')
   return building_comp and building_comp:get_building_quality()
end

return AceStructure
