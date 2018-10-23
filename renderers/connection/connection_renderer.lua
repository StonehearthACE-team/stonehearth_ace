local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local log = radiant.log.create_logger('connection_renderer')
local ConnectionRenderer = class()

function ConnectionRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._datastore = datastore
   self._entity = self._render_entity:get_entity()
   self._connections = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:connection')
   self._parent_node = self._render_entity:get_node()
   self._outline_nodes = {}

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._connection_update_listener = radiant.events.listen(self._entity:get_id(), 'stonehearth_ace:connections:entity_updated', self, self._update)
   self._boxed_region = radiant.alloc_region3()
end

function ConnectionRenderer:activate()
   self._position_trace = radiant.entities.trace_grid_location(self._entity, 'connection entity position trace')
         -- since the event is async, new_location might be off by one cycle
         :on_changed(function(new_location)
            if radiant.entities.is_entity_suspended(self._entity) then
               return
            end
            self:_update()
         end)
end

function ConnectionRenderer:destroy()

   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   if self._position_trace then
      self._position_trace:destroy()
      self._position_trace = nil
   end

   self:_destroy_outline_nodes()
end

function ConnectionRenderer:_destroy_outline_nodes()
   for type, nodes in pairs(self._outline_nodes) do
      for i, node in ipairs(nodes) do
         node:destroy()
         nodes[i] = nil
      end
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

   --local location = radiant.entities.get_world_grid_location(self._entity)
   --local facing = radiant.entities.get_facing(self._entity)

   -- go through each connector this entity has and render stuff for it
   for type, connection in pairs(self._connections) do
      local nodes = {}
      self._outline_nodes[type] = nodes

      local colors = stonehearth_ace.connection_client:get_connection_type_colors(type) or
         {connected = Point3(255, 0, 255), disconnected = Point3(192, 64, 192)}
      
      for name, connector in pairs(connection.connectors) do
         local color = colors.disconnected
         local EDGE_COLOR_ALPHA = 24
         local FACE_COLOR_ALPHA = 8

         local connected = stonehearth_ace.connection_client:is_connector_connected(type, self._entity:get_id(), name)
         if connected then
            color = colors.connected
         else
            EDGE_COLOR_ALPHA = EDGE_COLOR_ALPHA / 2
            FACE_COLOR_ALPHA = FACE_COLOR_ALPHA / 2
         end

         local region = Region3(radiant.util.to_cube3(connector.region):inflated(Point3(-0.3, -0.3, -0.3)))
         region:optimize('connector region')

         local render_node = _radiant.client.create_region_outline_node(self._parent_node, region,
            radiant.util.to_color4(color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA),
            '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json', '/stonehearth/data/horde/materials/debug_shape_nodepth.material.json', 0)

         local face_render_node = _radiant.client.create_region_outline_node(RenderRootNode, region,
            radiant.util.to_color4(color, EDGE_COLOR_ALPHA * 8), radiant.util.to_color4(color, FACE_COLOR_ALPHA * 5),
            '/stonehearth/data/horde/materials/transparent_box.material.json', '/stonehearth/data/horde/materials/debug_shape.material.json', 0)
         
         face_render_node:set_parent(render_node)
         render_node:add_reference_to(face_render_node)
         table.insert(nodes, render_node)
      end
   end
end

return ConnectionRenderer
