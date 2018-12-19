local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local FenceRenderer = class()
local log = radiant.log.create_logger('fence.renderer')

function FenceRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('joiner node')

   self._datastore = datastore
   self._joiner_nodes = {}

   local fence_data = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:fence')
   self._joiner_model_offset = radiant.util.to_point3(fence_data.joiner_model_offset)
   self._scale = fence_data.scale or 0.1

   self._datastore_trace = self._datastore:trace('drawing fence')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function FenceRenderer:destroy()
   self:_destroy_joiner_nodes()
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function FenceRenderer:_destroy_joiner_nodes()
   for _, node in ipairs(self._joiner_nodes) do
      node:destroy()
   end
   self._joiner_nodes = {}
end

function FenceRenderer:_update()
   self:_destroy_joiner_nodes()
   
   local data = self._datastore:get_data()
   local joiners = data.joiners

   if next(joiners) then
      for _, joiner in pairs(joiners) do
         self:_create_node(self._joiner_model_offset, self._scale, joiner)
      end
   end
end

function FenceRenderer:_create_node(offset, scale, joiner)
   if joiner and joiner.model then
      local rotation = joiner.rotation
      local node = _radiant.client.create_qubicle_matrix_node(self._node, joiner.model, 'fence',
            Point3(offset.x, offset.y, offset.z))
      if node then
         node:set_transform(0, 0, 0, 0, rotation, 0, scale, scale, scale)
         node:set_material('materials/voxel.material.json')
         --node:set_visible(true)
         table.insert(self._joiner_nodes, node)
      else
         --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
      end
   end
end

return FenceRenderer
