local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local PastureItemRenderer = class()
local log = radiant.log.create_logger('pasture_item_renderer')

function PastureItemRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_id = self._entity:get_id()
   self._entity_node = render_entity:get_node()

   self._component_data = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:pasture_item')
   self._trough_feed_data = radiant.resources.load_json('stonehearth_ace:data:trough_feed')

   self._datastore = datastore
   self._datastore_trace = self._datastore:trace('drawing pasture item')
                                          :on_changed(function ()
                                                self:_update_render()
                                             end)
                                          :push_object_state()
end

function PastureItemRenderer:destroy()
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   self:_destroy_trough_feed_node()
end

function PastureItemRenderer:_destroy_trough_feed_node()
   if self._trough_feed_node then
      self._trough_feed_node:destroy()
      self._trough_feed_node = nil
   end
end

function PastureItemRenderer:_update_render()
   self:_destroy_trough_feed_node()
   local feed = self._datastore:get_data().trough_feed_uri
   local trough_type = self._component_data.feed_model_trough_type
   if feed and trough_type then
      local data = self._trough_feed_data[trough_type]
      local feed_data = data and data.feed and data.feed[feed]
      if feed_data then
         self:_create_trough_feed_node(feed_data)
      end
   end
end

function PastureItemRenderer:_create_trough_feed_node(feed_data)
   local node = _radiant.client.create_qubicle_matrix_node(self._entity_node, feed_data.model, 'feed', Point3(0, 0, 0))
   if node then
      -- scale the feed model on x and y to fit into the trough
      local offset = radiant.util.to_point3(feed_data.origin):scaled(feed_data.scale)
      node:set_transform(offset.x, offset.y, offset.z, 0, 0, 0, feed_data.scale, feed_data.scale, feed_data.scale)
      node:set_material('materials/voxel.material.json')
      self._trough_feed_node = node
   end
end

return PastureItemRenderer
