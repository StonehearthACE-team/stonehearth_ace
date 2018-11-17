local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local ConnectionUtils = require 'lib.connection.connection_utils'
local import_region = ConnectionUtils.import_region

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

   self._datastore_trace = self._datastore:trace_data('entity connection available and connector status')
      :on_changed(function()
            self:_update()
         end
      )
      :push_object_state()

   self._position_trace = radiant.entities.trace_grid_location(self._entity, 'connection entity position trace')
      :on_changed(function(new_location)
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

   local data = self._datastore:get_data().connected_stats

   -- go through each connector this entity has and render stuff for it
   for type, connection in pairs(self._connections) do
      local type_data = data[type] or {}
      local available = type_data.available
      local connected = type_data.connected

      local origin_offset = radiant.util.to_point3(connection.origin_offset) or Point3.zero
      
      local nodes = {}
      self._outline_nodes[type] = nodes

      local colors = stonehearth_ace.connection_client:get_connection_type_colors(type) or
         stonehearth_ace.connection_client:get_connection_type_colors('default')
      
      for name, connector in pairs(connection.connectors) do
         local color = nil
         local EDGE_COLOR_ALPHA = 12
         local FACE_COLOR_ALPHA = 6
         
         local connector_available = (type_data.available_connectors or {})[name]
         local connector_connected = (type_data.connected_connectors or {})[name]
         local is_available = available and connector_available
         local is_connected = connected and connector_connected
         if is_available and colors.available_color then
            color = colors.available_color
         elseif is_connected and colors.connected_color then
            color = colors.connected_color
         end

         -- only render actually available or connected connectors
         if color and (is_available or is_connected) then
            local r = import_region(connector.region):translated(origin_offset)
            local inflation = Point3(-0.4, -0.4, -0.4)
            --[[
            for _, dir in ipairs({'x', 'y', 'z'}) do
               if cube.max[dir] - cube.min[dir] <= 1 then
                  inflation[dir] = -0.4
               end
            end
            ]]
            local region = r:inflated(inflation)
            region:optimize('connector region')
            
            local render_node = _radiant.client.create_region_outline_node(self._parent_node, region,
               radiant.util.to_color4(color, EDGE_COLOR_ALPHA * 8), radiant.util.to_color4(color, FACE_COLOR_ALPHA * 5),
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
end

return ConnectionRenderer
