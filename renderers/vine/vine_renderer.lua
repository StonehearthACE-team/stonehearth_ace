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
   
   local data = self._datastore:get_data()
   local options = data.render_options
   local render_dirs = data.render_directions
   local casts_shadows = data.casts_shadows
   if not render_dirs or not next(render_dirs) then
      return
   end

   local entity_node_pos = self._entity_node:get_position()
   self._entity_node:set_aabb(Cube3(Point3.zero + entity_node_pos, Point3.one + entity_node_pos))

   --log:error('render_directions: %s', radiant.util.table_tostring(render_dirs))
   for dir, _ in pairs(render_dirs) do
      if dir == 'y+' then
         self:_create_node(options.faces.top, 0, casts_shadows)
      elseif dir == 'y-' then
         self:_create_node(options.faces.bottom, 0, casts_shadows)
      else
         self:_create_node(options.faces.side, _rotations[dir] or 0, casts_shadows)
      end
   end
end

function VineRenderer:_create_node(options, rotation, casts_shadows)
   if options and options.model then
      rotation = (360 - self._facing + rotation) % 360
      local node = _radiant.client.create_qubicle_matrix_node(self._node, options.model, 'background',
            Point3(options.origin.x, options.origin.y, options.origin.z))
      if node then
         --node:set_casts_shadows(casts_shadows)
         node:set_transform(0, 0, 0, 0, rotation, 0, options.scale, options.scale, options.scale)
         node:set_material('materials/voxel.material.json')
         --node:set_visible(true)
         table.insert(self._vine_nodes, node)
      else
         --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
      end
   end
end

return VineRenderer
