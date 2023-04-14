local ZoneRenderer = require 'stonehearth.renderers.zone_renderer'
local Color4 = _radiant.csg.Color4
local Point2 = _radiant.csg.Point2

local AceShepherdPastureRenderer = class()

-- Overriding this to change the color
function AceShepherdPastureRenderer:initialize(render_entity, datastore)
   self._datastore = datastore

   self._zone_renderer = ZoneRenderer(render_entity):set_ground_colors(Color4(77, 62, 38, 10), Color4(77, 62, 38, 30))

   self._datastore_trace = self._datastore:trace_data('rendering shepherd pasture')
      :on_changed(
         function()
            self:_update()
         end
      )
      :push_object_state()
end

function AceShepherdPastureRenderer:_update()
   local data = self._datastore:get_data()
   local size = data.size
   local items = {}

   local c = Color4(unpack(data.zone_color or {227, 173, 44, 204}))
   self._zone_renderer:set_designation_colors(c, c)

   self._zone_renderer:set_size(Point2(data.size.x, data.size.z))
   self._zone_renderer:set_current_items(items)
end

return AceShepherdPastureRenderer
