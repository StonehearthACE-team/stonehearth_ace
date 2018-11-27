local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local PatrolBannerRenderer = class()
local log = radiant.log.create_logger('patrol_banner_renderer')

local Y_OFFSET = 0.5
local HILIGHT_COLOR = Point3(0.5, 0.5, 0.5)
local PATH_COLOR = {255, 255, 255, 224}

function PatrolBannerRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()

   self._datastore = datastore
   self._path_node = RenderRootNode:add_debug_shapes_node('patrol_banner path from '..tostring(self._entity))

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)

   self._datastore_trace = self._datastore:trace('drawing patrol_banner')
                                          :on_changed(function ()
                                                self:_update_render()
                                             end)
                                          :push_object_state()
end

function PatrolBannerRenderer:destroy()
   if self._path_node then
      self._path_node:destroy()
      self._path_node = nil
   end
   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function PatrolBannerRenderer:_in_appropriate_mode()
   return true --self._ui_view_mode == 'military' or self._ui_view_mode == 'hud' or self._ui_view_mode == 'build'
end

function PatrolBannerRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update_render()
   end
end

function PatrolBannerRenderer:_update_render()
   self._path_node:clear()
   
   if _radiant.client.get_player_id() == self._entity:get_player_id() and self:_in_appropriate_mode() then
      local data = self._datastore:get_data()
      --local options = data.render_options
      local path = data.path_to_next_banner or {}
      local path_color = Color4(unpack(data.path_color or PATH_COLOR))

      --local entity_node_pos = self._entity_node:get_position()
      --self._entity_node:set_aabb(Cube3(Point3.zero + entity_node_pos, Point3.one + entity_node_pos))

      --log:error('render_directions: %s', radiant.util.table_tostring(render_dirs))
      
      self._entity_node:set_visible(true)
      _radiant.client.hilight_entity(self._entity, HILIGHT_COLOR)
      self:_create_path(path, path_color)
   else
      self._entity_node:set_visible(false)
   end

   self._path_node:create_buffers()
end

--[[
function PatrolBannerRenderer:_create_node(options, rotation)
   if options and options.model then
      rotation = (360 - self._facing + rotation) % 360
      local node = _radiant.client.create_qubicle_matrix_node(self._entity_node, options.model, 'background',
            Point3(options.origin.x, 0, options.origin.z))
      if node then
         local offset = options.origin:scaled(options.scale)
         node:set_transform(offset.x, offset.y, offset.z, 0, rotation, 0, options.scale, options.scale, options.scale)
         node:set_material('materials/voxel.material.json')
         --node:set_visible(true)
         table.insert(self._vine_nodes, node)
      end
   end
end
]]

function PatrolBannerRenderer:_create_path(path, path_color)
   if path and stonehearth.subterranean_view:is_visible(self._entity) then
      local last_point = Point3()
      local point = Point3()
      local location = radiant.entities.get_world_location(self._entity)
      if location then
         local x, y, z = location:get_xyz()
         last_point:set(x, y + Y_OFFSET, z)

         for i, path_point in ipairs(path) do
            x, y, z = path_point:get_xyz()
            point:set(x, y + Y_OFFSET, z)
            self._path_node:add_line(last_point, point, path_color)
            last_point, point = point, last_point
         end
      end
   end
end

return PatrolBannerRenderer
