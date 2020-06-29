local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local fixture_utils = require 'stonehearth.lib.building.fixture_utils'

local WaterPumpRenderer = class()
local log = radiant.log.create_logger('water_pump.renderer')

function WaterPumpRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('pipes node')

   self._datastore = datastore
   self._pipe_nodes = {}

   self._datastore_trace = self._datastore:trace('drawing pipe')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function WaterPumpRenderer:destroy()
   self:_destroy_pipe_nodes()
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function WaterPumpRenderer:_destroy_pipe_nodes()
   for _, node in ipairs(self._pipe_nodes) do
      node:destroy()
   end
   self._pipe_nodes = {}
end

function WaterPumpRenderer:_update()
   self:_destroy_pipe_nodes()

   local data = self._datastore:get_data().pipe_render_data or {}
   self:_create_nodes(data)
end

function WaterPumpRenderer:_create_nodes(data)
   local model = data.model
   local origin = data.origin
   local direction = data.direction
   local length = data.length

   if model and origin and direction and length then
      for i = 1, length do
         self:_create_node(origin + (direction * (i - 1)), data)
      end
   end
end

function WaterPumpRenderer:_create_node(location, data)
   log:debug('rendering node at %s: %s', location, radiant.util.table_tostring(data))
   local model = data.model
   local model_offset = data.model_offset or Point3.zero
   local matrix = data.matrix or 'pipe'
   local scale = data.scale or 0.1

   local node = _radiant.client.create_qubicle_matrix_node(self._node, model, matrix, Point3(model_offset.x, model_offset.y, model_offset.z))

   if node then
      local rotation = data.rotation or fixture_utils.rotation_from_direction(data.direction)
      local material = data.material or 'materials/voxel.material.json'
      --log:debug('%s rendering %s at %s scale at %s', self._entity, model, scale, location)
      node:set_transform(location.x, location.y, location.z, 0, rotation, 0, scale, scale, scale)
      node:set_material(material)
      --node:set_visible(true)
      table.insert(self._pipe_nodes, node)
   end
end

return WaterPumpRenderer
