local AcePostureComponent = class()

function AcePostureComponent:get_postures()
   local postures = {}
   for i = 1, #self._requested_postures do
      postures[i] = self._requested_postures[i]
   end
   return postures
end

return AcePostureComponent
