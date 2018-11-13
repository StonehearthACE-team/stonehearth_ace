local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local VineRenderer = class()
local log = radiant.log.create_logger('vine.renderer')

local _rotations = {
   ['x-'] = 90,
   ['z+'] = 180,
   ['x+'] = 270,
   ['z-'] = 0
}

function VineRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('vine node')

   self._datastore = datastore
   self._vine_nodes = {}

   -- Pull some render parameters out of the entity data
   local ed = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:vine_render_info')
   self._bottom_model = ed.bottom_model
   self._top_model = ed.top_model
   self._side_model = ed.side_model
   self._scale = ed.scale and ed.scale or 0.1
   if ed.origin then
      self._origin = Point3(ed.origin.x, ed.origin.y, ed.origin.z)
   else
      self._origin = Point3(0, 0, 0)
   end
   self._facing = radiant.entities.get_facing(self._entity)

   self._datastore_trace = self._datastore:trace('drawing vines')
                                          :on_changed(function ()
                                                self:_update_render()
                                             end)
                                          :push_object_state()
end

function VineRenderer:destroy()
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function VineRenderer:_destroy_vine_nodes()
   for _, node in pairs(self._vine_nodes) do
      node:destroy()
   end
   self._vine_nodes = {}
end

function VineRenderer:_update_render()
   self:_destroy_vine_nodes()
   
   local render_dirs = self._datastore:get_data().render_directions
   if not render_dirs or not next(render_dirs) then
      return
   end

   local entity_node_pos = self._entity_node:get_position()
   self._entity_node:set_aabb(Cube3(Point3.zero + entity_node_pos, Point3.one + entity_node_pos))

   --log:error('render_directions: %s', radiant.util.table_tostring(render_dirs))
   for dir, _ in pairs(render_dirs) do
      if dir == 'y+' then
         self:_create_node(self._top_model, 0, true)
      elseif dir == 'y-' then
         self:_create_node(self._bottom_model, 0)
      else
         self:_create_node(self._side_model, _rotations[dir])
      end
   end
end

function VineRenderer:_create_node(model, rotation, is_top)
   if model then
      rotation = (360 - self._facing + rotation) % 360
      local node = _radiant.client.create_qubicle_matrix_node(self._node, model, 'background', self._origin)
      if node then
         local offset = self._origin:scaled(self._scale)
         node:set_transform(offset.x, offset.y + (is_top and 1 or 0), offset.z, is_top and 180 or 0, rotation, 0, self._scale, self._scale, self._scale)
         node:set_material('materials/voxel.material.json')
         --node:set_visible(true)
         table.insert(self._vine_nodes, node)
      else
         --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
      end
   end
end

return VineRenderer
