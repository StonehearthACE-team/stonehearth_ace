local Point3 = _radiant.csg.Point3
local fixture_utils = require 'stonehearth.lib.building.fixture_utils'

local ModelsRenderer = class()
local log = radiant.log.create_logger('models.renderer')

function ModelsRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('model node')

   self._datastore = datastore
   self._model_nodes = {}

   self._datastore_trace = self._datastore:trace('drawing models')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function ModelsRenderer:destroy()
   self:_destroy_model_nodes()
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

-- it might make more sense to just destroy and recreate self._node each time
-- unless we want to keep track of separate model nodes and actually "update" them
-- which could allow us to include some animations; maybe that's an overextension?
function ModelsRenderer:_destroy_model_nodes()
   for _, node in pairs(self._model_nodes) do
      if node.primary_node then
         node.primary_node:destroy()
      end
      if node.child_nodes then
         for _, child in ipairs(node.child_nodes) do
            child:destroy()
         end
      end
   end
   self._model_nodes = {}
end

function ModelsRenderer:_update()
   self:_destroy_model_nodes()
   
   local data = self._datastore:get_data()
   local models = data.models

   for name, model in pairs(models) do
      local node = self:_create_node(model)
      if node then
         self._model_nodes[name] = node
      end
   end
end

function ModelsRenderer:_create_node(options)
   if options and options.model and options.visible then
      local node = {}
      local origin = options.origin or Point3.zero
      local rotation = options.rotation or (options.direction and fixture_utils.rotation_from_direction(options.direction)) or 0
      local offset = radiant.util.to_point3(options.offset) or Point3.zero
      local scale = options.scale or 0.1
      if options.scale_with_entity then
         scale = scale * self._entity:get_component('render_info'):get_scale()
      end
      local model = options.model
      local matrix = options.matrix or 'background'
      local material = options.material or 'materials/voxel.material.json'

      if options.origin and options.direction and options.length then
         if options.length > 0 then
            -- make a group node and add a bunch of child nodes to it
            node.primary_node = self._node:add_group_node('directional group node')
            node.child_nodes = {}

            for i = 0, options.length - 1 do
               local child = self:_create_single_node(node.primary_node, origin + options.direction * i, rotation, offset, scale, model, matrix, material)
               if child then
                  table.insert(node.child_nodes, child)
               end
            end
         end
      else
         node.primary_node = self:_create_single_node(self._node, origin, rotation, offset, scale, model, matrix, material)
      end
      
      return node
   end
end

function ModelsRenderer:_create_single_node(parent_node, location, rotation, offset, scale, model, matrix, material)
   local node = _radiant.client.create_qubicle_matrix_node(parent_node, model, matrix, offset)
   if node then
      node:set_transform(location.x, location.y, location.z, 0, rotation, 0, scale, scale, scale)
      node:set_material(material)
      return node
   else
      --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
   end
end

return ModelsRenderer
