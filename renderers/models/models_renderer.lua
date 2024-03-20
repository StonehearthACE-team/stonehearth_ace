local Point3 = _radiant.csg.Point3
local fixture_utils = require 'stonehearth.lib.building.fixture_utils'

local ModelsRenderer = class()
local log = radiant.log.create_logger('models.renderer')

function ModelsRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   
   if self._entity_node then
      self._node = self._entity_node:add_group_node('model node')

      self._datastore = datastore
      self._model_nodes = {}

      self._datastore_trace = self._datastore:trace('drawing models')
                                             :on_changed(function ()
                                                   self:_update()
                                                end)
                                             :push_object_state()
   end
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
      for _, sub_nodes in pairs(node.sub_nodes) do
         if sub_nodes.primary_node then
            sub_nodes.primary_node:destroy()
         end
         if sub_nodes.child_nodes then
            for _, child in ipairs(sub_nodes.child_nodes) do
               child:destroy()
            end
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
      local node = self:_create_named_node(model)
      if node then
         self._model_nodes[name] = node
      end
   end
end

function ModelsRenderer:_create_named_node(options)
   if options and options.visible then
      -- either this is a table with data for a single model,
      -- or it is a table with a 'models' entry that is a list of multiple model data tables
      if options.models and #options.models > 0 or options.model then
         local node = { sub_nodes = {} }
         for _, model in ipairs(options.models or {options}) do
            if model.model then
               table.insert(node.sub_nodes, self:_create_model_nodes(model))
            end
         end
         
         if #node.sub_nodes > 0 then
            return node
         end
      end
   end
end

function ModelsRenderer:_create_model_nodes(options)
   local node = { child_nodes = {} }
   local origin = options.origin or Point3.zero
   local rotation = options.rotation or (options.direction and fixture_utils.rotation_from_direction(options.direction)) or 0
   local offset = radiant.util.to_point3(options.offset) or Point3.zero
   local scale = options.scale or 0.1
   if options.scale_with_entity then
      scale = scale * self._entity:get_component('render_info'):get_scale()
   end
   local model = options.model
   local matrix = options.matrix or 'background'
   local multi_matrix_mode = options.multi_matrix_mode or 'all'
   local material = options.material or 'materials/voxel.material.json'

   if options.origin and options.direction and options.length then
      if options.length > 0 then
         -- make a group node and add a bunch of child nodes to it
         node.primary_node = self._node:add_group_node('directional group node')

         -- if the direction is negative and the region offset is positive in that dimension, we need to increment it by one
         -- (because we're approaching from the other side of the voxel)
         if options.direction[options.dimension] < 0 then
            local region_origin = self._entity:get_component('mob'):get_region_origin()
            --log:debug('shifting model render: %s, %s, %s, %s', origin, options.direction, region_origin, options.dimension)
            origin = origin + options.direction * math.floor(0.5 + region_origin[options.dimension])
            --log:debug('new origin: %s', origin)
         end

         for i = 0, options.length - 1 do
            self:_create_matrix_nodes(node, origin + options.direction * i, rotation, offset, scale, model, matrix, multi_matrix_mode, material, i)
         end
      end
   else
      self:_create_matrix_nodes(node, origin, rotation, offset, scale, model, matrix, multi_matrix_mode, material)
   end

   return node
end

-- create a node for each matrix specified
-- if there's no primary_node specified, set the first created node to that
-- any additional nodes should be added to child_nodes
function ModelsRenderer:_create_matrix_nodes(group, location, rotation, offset, scale, model, matrix, multi_matrix_mode, material, index)
   local matrices = radiant.util.is_table(matrix) and matrix or {matrix}
   if multi_matrix_mode == 'sequential' then
      matrices = {matrices[index % #matrices + 1]}
   end

   for _, this_matrix in ipairs(matrices) do
      local node = self:_create_single_node(group.primary_node or self._node, location, rotation, offset, scale, model, this_matrix, material)
      if node then
         table.insert(group.child_nodes, node)
      end
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
