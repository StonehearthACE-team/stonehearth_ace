local XYZRangeSelector = require 'stonehearth_ace.services.client.selection.range_selector'

local AceSelectionService = class()

function AceSelectionService:select_xyz_range(reason)
   return XYZRangeSelector(reason)
end

return AceSelectionService
