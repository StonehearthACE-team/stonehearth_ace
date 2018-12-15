local Point3 = _radiant.csg.Point3

local TileRenderer = class()

function TileRenderer:initialize(render_entity, datastore)
   self._datastore = datastore
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   
   local comp_data = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:tile')
   self._origin = comp_data.origin or Point3.zero
   self._scale = comp_data.scale or 1

   self._datastore_trace = self._datastore:trace_data('rendering tile')
      :on_changed(
         function()
            self:_update()
         end
      )
      :push_object_state()
end

function TileRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function TileRenderer:_update()
   local data = self._datastore:get_data()
   local rotation = data.rotation
   self._entity_node:set_transform(self._origin.x, self._origin.y, self._origin.z, 0, rotation, 0, self._scale, self._scale, self._scale)
end

return TileRenderer
