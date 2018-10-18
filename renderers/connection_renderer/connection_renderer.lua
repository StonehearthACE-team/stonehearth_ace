local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local ConnectionRenderer = class()

function ConnectionRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._datastore = datastore
   self._entity = self._render_entity:get_entity()
   self._connections = self._entity:get_component('stonehearth_ace:connection'):get_connections()
   self._parent_node = self._render_entity:get_node()
   self._outline_nodes = {}

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._boxed_region = radiant.alloc_region3()

   self._position_trace = radiant.entities.trace_grid_location(self._entity, 'connection entity position trace')
      -- since the event is async, new_location might be off by one cycle
      :on_changed(function(new_location)
         if is_entity_suspended(self._entity) then
            return
         end
         self:_update()
      end)
end

function ConnectionRenderer:destroy()

   _radiant.renderer.remove_terrain_cut(self._boxed_region)

   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   if self._visible_volume_trace then
      self._visible_volume_trace:destroy()
      self._visible_volume_trace = nil
   end

   if self._presence_client_listener then
      self._presence_client_listener:destroy()
      self._presence_client_listener = nil
   end

   if self._multiplayer_listener then
      self._multiplayer_listener:destroy()
      self._multiplayer_listener = nil
   end

   if self._destination_trace then
      self._destination_trace:destroy()
      self._destination_trace = nil
   end

   self:_destroy_outline_node()
end

function ConnectionRenderer:_destroy_outline_nodes()
   for key, node in pairs(self._outline_nodes) do
      node:destroy()
      self._outline_nodes[key] = nil
   end
end

function ConnectionRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function ConnectionRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'hud' or self._ui_view_mode == 'place'
end

function ConnectionRenderer:_update()
   self:_destroy_outline_nodes()

   if not self:_in_appropriate_mode() then
      return
   end

   -- Believe it or not, doing this in the initializer isn't correct, as
   -- apparently the root might not exist (on load!)
   -- This is basically free, though, so just set the cut on every update.
   _radiant.renderer.add_terrain_cut(self._boxed_region)

   local location = radiant.entities.get_world_grid_location(self._entity)
   local data = self._datastore:get_data()
   local working_region = data.region:get():translated(location)
   local completed = radiant.terrain.clip_region(working_region)

   working_region = stonehearth.subterranean_view:intersect_region_with_visible_volume(working_region)
   working_region = working_region - completed
   working_region:optimize('mining zone renderer')
   working_region = working_region:inflated(Point3(0.001, 0.001, 0.001))  -- Puff it out so there's a floating region.

   working_region:translate(-location)


   local player_id = radiant.entities.get_player_id(self._entity)
   local color = { x = 255, y = 255, z = 0 } -- ye olde default
   if stonehearth.presence_client:is_multiplayer() then
      color = stonehearth.presence_client:get_player_color(player_id)
   end

   local EDGE_COLOR_ALPHA = 24
   local FACE_COLOR_ALPHA = 8

   -- go through each connector this entity has and 
   local render_node = _radiant.client.create_region_outline_node(self._parent_node, working_region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA), 'materials/transparent_box_nodepth.material.json', 'materials/debug_shape_nodepth.material.json', 0)
   local face_render_node = _radiant.client.create_region_outline_node(RenderRootNode, working_region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA * 8), radiant.util.to_color4(color, FACE_COLOR_ALPHA * 5), 'materials/transparent_box.material.json', 'materials/debug_shape.material.json', 0)
   face_render_node:set_parent(render_node)
   render_node:add_reference_to(face_render_node)
   self._outline_node = render_node

   --stonehearth.selection:set_selectable(self._entity, data.selectable)
end

return ConnectionRenderer
