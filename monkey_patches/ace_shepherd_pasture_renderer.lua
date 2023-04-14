local ZoneRenderer = require 'stonehearth.renderers.zone_renderer'
local Color4 = _radiant.csg.Color4
local Point2 = _radiant.csg.Point2

local AceShepherdPastureRenderer = class()

-- Overriding this to change the color
function AceShepherdPastureRenderer:initialize(render_entity, datastore)
   self._datastore = datastore

   self._zone_renderer = ZoneRenderer(render_entity)
      -- TODO: read these colors from json
      :set_designation_colors(Color4(227, 173, 44, 255), Color4(227, 173, 44, 255))
      :set_ground_colors(Color4(77, 62, 38, 10), Color4(77, 62, 38, 30))

   self._datastore_trace = self._datastore:trace_data('rendering shepherd pasture')
      :on_changed(
         function()
            self:_update()
         end
      )
      :push_object_state()
end

return AceShepherdPastureRenderer
