-- largely ripped from landmark_renderer
local PlaceTerrainRenderer = class()

local log = radiant.log.create_logger('place_terrain_renderer')

function PlaceTerrainRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = self._render_entity:get_entity()
   self._datastore = datastore
   
   self._datastore_trace = self._datastore:trace('drawing terrain')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function PlaceTerrainRenderer:destroy()
   self:_destroy_nodes()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function PlaceTerrainRenderer:_destroy_nodes()
   if self._visualization_node then
      self._visualization_node:destroy()
      self._visualization_node = nil
   end
end

function PlaceTerrainRenderer:_update()
   self:_destroy_nodes()

   local spec = self._datastore:get_data().spec

   local color = radiant.util.to_point3(_radiant.renderer.get_color(spec.terrain_tag))
   local region = spec.region

   self._visualization_node = _radiant.client.create_region_outline_node(
      self._render_entity:get_node(), region, radiant.util.to_color4(color, 160), radiant.util.to_color4(color, 224),
      '/stonehearth/data/horde/materials/transparent_with_depth.material.json', '/stonehearth/data/horde/materials/debug_shape.material.json', 0)
end

return PlaceTerrainRenderer
