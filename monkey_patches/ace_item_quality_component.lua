local AceItemQualityComponent = class()

local NO_QUALITY = -1

function AceItemQualityComponent:is_initialized()
   return self._sv.quality ~= NO_QUALITY
end

return AceItemQualityComponent
