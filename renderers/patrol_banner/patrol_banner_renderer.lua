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
   self._entity_id = self._entity:get_id()
   self._entity_node = render_entity:get_node()

   self._datastore = datastore
   self._path_node = RenderRootNode:add_debug_shapes_node('patrol_banner path from '..tostring(self._entity))

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._hilight_changed_listener = radiant.events.listen(self._entity, 'stonehearth:hilighted_changed', self, self._on_hilight_changed)
   self._selection_changed_listener = radiant.events.listen(self._entity, 'stonehearth:selection_changed', self, self._on_hilight_changed)

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
   if self._hilight_changed_listener then
      self._hilight_changed_listener:destroy()
      self._hilight_changed_listener = nil
   end
   if self._selection_changed_listener then
      self._selection_changed_listener:destroy()
      self._selection_changed_listener = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function PatrolBannerRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'military' or self._ui_view_mode == 'hud' or self._ui_view_mode == 'build'
end

function PatrolBannerRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update_render()
   end
end

--[[
   when the player has an entity selected, we want to reset our hilighting on it
   when the player mouses ON an unselected entity, we want to reset our hilighting on it
   when the player mouses OFF an unselected entity, we want to re-enable our hilighting on it
]]
function PatrolBannerRenderer:_on_hilight_changed()
   self:_update_render()
end

function PatrolBannerRenderer:_do_hilight_check()
   local hilighted = stonehearth.hilight:get_hilighted()
   local selected = stonehearth.selection:get_selected()

   --log:debug('_do_hilight_check for %s (is_hilighted = %s): hilighted = %s, selected = %s', self._entity, self._is_hilighted or 'NIL', hilighted or 'NIL', selected or 'NIL')
   if selected == self._entity then
      if self._is_hilighted then
         self:_unhilight()
         stonehearth.hilight:hilight_entity(self._entity)
         return true
      end
   elseif hilighted == self._entity then
      if self._is_hilighted then
         self:_unhilight()
         stonehearth.hilight:hilight_entity(self._entity)
         return true
      end
   else
      self:_unhilight()
   end

   return false
end

function PatrolBannerRenderer:_unhilight()
   self._is_hilighted = false
   _radiant.client.unhilight_entity(self._entity_id)
   local _hilight_count = stonehearth.hilight._hilight_count
   if _hilight_count[self._entity_id] then
      _hilight_count[self._entity_id] = 0
   end
end

function PatrolBannerRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'hud' or self._ui_view_mode == 'place'
end

function PatrolBannerRenderer:_update_render()
   local ignore_hilighting = self:_do_hilight_check()
   self._path_node:clear()

   if _radiant.client.get_player_id() == self._entity:get_player_id() and self:_in_appropriate_mode() then
      local data = self._datastore:get_data()
      local path = data.path_to_next_banner or {}
      local path_color = Color4(unpack(data.path_color or PATH_COLOR))

      self._entity_node:set_visible(true)
      if not ignore_hilighting then
         self._is_hilighted = true
         _radiant.client.hilight_entity(self._entity, Point3(path_color.r / 255, path_color.g / 255, path_color.b / 255))
      end
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
