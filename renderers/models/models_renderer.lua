local Point3 = _radiant.csg.Point3

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

function ModelsRenderer:_destroy_model_nodes()
   for _, node in ipairs(self._model_nodes) do
      node:destroy()
   end
   self._model_nodes = {}
end

function ModelsRenderer:_update()
   self:_destroy_model_nodes()
   
   local data = self._datastore:get_data()
   local models = data.models

   for _, model in pairs(models) do
      self:_create_node(model)
   end
end

function ModelsRenderer:_create_node(options)
   if options and options.model and options.visible then
      local rotation = options.rotation or 0
      local offset = radiant.util.to_point3(options.offset) or Point3.zero
      local scale = options.scale or 0.1
      if options.scale_with_entity then
         scale = scale * self._entity:get_component('render_info'):get_scale()
      end
      local node = _radiant.client.create_qubicle_matrix_node(self._node, options.model, options.matrix or 'background', offset)
      if node then
         node:set_transform(0, 0, 0, 0, rotation, 0, scale, scale, scale)
         node:set_material(options.material or 'materials/voxel.material.json')
         table.insert(self._model_nodes, node)
      else
         --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
      end
   end
end

return ModelsRenderer
