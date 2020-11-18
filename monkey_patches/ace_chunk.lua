local AceChunk = class()

function AceChunk:get_owning_structure()
   return self._sv._owning_structure
end

function AceChunk:get_owning_building()
   local structure = self._sv._owning_structure
   local structure_comp = structure and structure:get_component('stonehearth:build2:structure')
   return structure_comp and structure_comp:get_owning_building()
end

return AceChunk
