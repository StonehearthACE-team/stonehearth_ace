local Bulletin = require 'stonehearth.services.server.bulletin_board.bulletin'
local AceBulletin = class()

function AceBulletin:get_data()
   return self._sv.data
end

return AceBulletin
