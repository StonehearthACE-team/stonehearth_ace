local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local PlantFieldAdjacent = require 'stonehearth.ai.actions.plant_field_adjacent_action'
local AcePlantFieldAdjacent = class()

AcePlantFieldAdjacent._old__plant_at_current_location = PlantFieldAdjacent._plant_at_current_location
function AcePlantFieldAdjacent:_plant_at_current_location()
   self:_old__plant_at_current_location()

   if self._location then
      local job_component = self._entity:get_component('stonehearth:job')
      if job_component and job_component:curr_job_has_perk('farmer_mega_crops') then
         local crop = self._farmer_field:crop_at(self._location)
         if crop then
            crop:get_component('stonehearth:crop'):set_consider_megacrop()
         end
      end
   end
end

return AcePlantFieldAdjacent
