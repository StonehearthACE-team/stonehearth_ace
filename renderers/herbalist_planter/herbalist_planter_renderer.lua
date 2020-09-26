local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local HerbalistPlanterRenderer = class()
local log = radiant.log.create_logger('herbalist_planter.renderer')

local all_plant_data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter:crops')

function HerbalistPlanterRenderer:initialize(render_entity, datastore)
   -- self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   -- self._node = self._entity_node:add_group_node('plants node')

   self._datastore = datastore
   self._plant_nodes = {}

   local planter_data = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:herbalist_planter')
   self._plant_locations = planter_data.plant_locations or {}
   self._scale_multiplier = planter_data.scale_multiplier or 1

   self._datastore_trace = self._datastore:trace('drawing planter')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function HerbalistPlanterRenderer:destroy()
   self:_destroy_plant_nodes()
   -- if self._node then
   --    self._node:destroy()
   --    self._node = nil
   -- end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function HerbalistPlanterRenderer:_destroy_plant_nodes()
   for _, node in ipairs(self._plant_nodes) do
      node:destroy()
   end
   self._plant_nodes = {}
end

function HerbalistPlanterRenderer:_update()
   local data = self._datastore:get_data()
   local plant = data.planted_crop
   local growth_level = data.crop_growth_level
   if plant == self._cur_plant and growth_level == self._cur_growth_level then
      return
   end

   self._cur_plant = plant
   self._cur_growth_level = growth_level
   self:_destroy_plant_nodes()

   if plant and growth_level then
      local plant_data = all_plant_data.crops[plant] or {}
      local growth_levels = plant_data.growth_levels or {}
      local growth_level_data = growth_levels[growth_level] or {}
      local render_scale = plant_data.render_scale or 0.1

      for _, location in ipairs(self._plant_locations) do
         self:_create_nodes(location, self._scale_multiplier * (growth_level_data.render_scale or render_scale), growth_level_data)
      end
   end
end

function HerbalistPlanterRenderer:_create_nodes(location, scale, growth_level_data)
   -- if this node data is an array, process through and create each node
   if growth_level_data.model then
      self:_create_node(location, scale, growth_level_data)
   elseif #growth_level_data > 0 then
      for _, data in ipairs(growth_level_data) do
         self:_create_node(location, scale, data)
      end
   end
end

function HerbalistPlanterRenderer:_create_node(location, scale, node_data)
   local model = node_data.model
   local offset = Point3(node_data.offset.x or 0, node_data.offset.y or 0, node_data.offset.z or 0)
   local matrix = node_data.matrix or 'crop'

   local node = _radiant.client.create_qubicle_matrix_node(self._entity_node, model, matrix, offset)

   if node then
      local position = Point3(-location.offset.x or 0, location.offset.y or 0, -location.offset.z or 0)
      local rotation = Point3(0, node_data.rotation or location.rotation or 0, 0)
      local material = node_data.material or 'materials/voxel.material.json'
      --log:debug('%s rendering %s at %s scale at %s', self._entity, model, scale, position)
      node:set_scale(Point3.one * scale)
      node:set_rotation(rotation)
      node:set_position(position)
      --node:set_transform(position.x, position.y, position.z, 0, rotation, 0, scale, scale, scale)
      node:set_material(material)
      --node:set_visible(true)
      table.insert(self._plant_nodes, node)
   end
end

return HerbalistPlanterRenderer
