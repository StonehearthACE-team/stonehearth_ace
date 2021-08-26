local AceLadderBuilder = class()

function AceLadderBuilder:get_ladder_proxy()
   return self._sv.ladder_dst_proxy
end

return AceLadderBuilder