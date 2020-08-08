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
   self._outline_nodes = {}
   self._connections = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:connection')
   self._show_connectors = radiant.util.get_config('show_connector_regions', true)

   local mob_data = radiant.entities.get_component_data(self._entity, 'mob')
   local align_to_grid = radiant.array_to_map(mob_data and mob_data.align_to_grid or {})
   local model_origin = mob_data and mob_data.model_origin and radiant.util.to_point3(mob_data.model_origin) or Point3.zero
   self._origin_offset = Point3(align_to_grid.x and 0.5 or 0, align_to_grid.y and 0.5 or 0, align_to_grid.z and 0.5 or 0) + model_origin
   self._parent_node = self._render_entity:get_node()
   self._outline_nodes = {}

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._in_selected_graphs_listener = radiant.events.listen(self._entity, 'stonehearth_ace:entity_in_selected_graphs_changed', self, self._on_entity_in_selected_graphs_changed)
   self._show_connectors_listener = radiant.events.listen(radiant, 'show_connector_regions_setting_changed', self, self._on_show_connectors_changed)
   --self._hilight_changed_listener = radiant.events.listen(self._entity, 'stonehearth:hilighted_changed', self, self._on_hilight_changed)

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

   if self._in_selected_graphs_listener then
      self._in_selected_graphs_listener:destroy()
      self._in_selected_graphs_listener = nil
   end

   if self._hilight_changed_listener then
      self._hilight_changed_listener:destroy()
      self._hilight_changed_listener = nil
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
   self:_destroy_hilight_tracker()
end

function ConnectionRenderer:_destroy_outline_nodes()
   for type, nodes in pairs(self._outline_nodes) do
      for i, node in ipairs(nodes) do
         node:destroy()
         nodes[i] = nil
      end
   end
end

function ConnectionRenderer:_destroy_hilight_tracker()
   if self._highlight_tracker then
      self._highlight_tracker:destroy()
      self._highlight_tracker = nil
   end
end

function ConnectionRenderer:_on_entity_in_selected_graphs_changed(in_selected_graphs)
   if in_selected_graphs ~= self._in_selected_graphs then
      self._in_selected_graphs = in_selected_graphs
      self:_update()
   end
end

--[[
   when the player has an entity selected, we want to reset our hilighting on it
   when the player mouses ON an unselected entity, we want to reset our hilighting on it
   when the player mouses OFF an unselected entity, we want to re-enable our hilighting on it
]]
function ConnectionRenderer:_on_hilight_changed()
   self:_update()
end

-- currently not getting called until fixed
function ConnectionRenderer:_do_hilight_check()
   local hilighted = stonehearth.hilight:get_hilighted()
   local selected = stonehearth.selection:get_selected()

   if selected == self._entity then
      if self._is_hilighted then
         self:_unhilight()
         self._highlight_tracker = stonehearth.hilight:hilight_entity(self._entity)
         return true
      end
   elseif hilighted == self._entity then
      if self._is_hilighted then
         self:_unhilight()
         self._highlight_tracker = stonehearth.hilight:hilight_entity(self._entity)
         return true
      end
   else
      self:_unhilight()
   end

   return false
end

function ConnectionRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function ConnectionRenderer:_on_show_connectors_changed(show)
   self._show_connectors = show
   self:_update()
end

function ConnectionRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'hud'
end

function ConnectionRenderer:_unhilight()
   self._is_hilighted = false
   self:_destroy_hilight_tracker()
end

function ConnectionRenderer:_update()
   self:_destroy_outline_nodes()
   local ignore_hilighting = true   --self:_do_hilight_check() -- TODO: fix the hilighting!

   if not self._show_connectors or not self:_in_appropriate_mode() then
      return
   end

   --local location = radiant.entities.get_world_grid_location(self._entity)
   --local facing = radiant.entities.get_facing(self._entity)

   local data = self._datastore:get_data()
   local connected_stats = data.connected_stats
   local hilight = {priority = -1}

   -- go through each connector this entity has and render stuff for it
   for _, connections in ipairs({self._connections, data.dynamic_connections}) do
      if connections then
         for type, connection in pairs(connections) do
            local type_data = connected_stats[type]
            local available = true
            local connected = false
            if type_data then
               available = type_data.num_connections < type_data.max_connections
               connected = type_data.num_connections > 0
            end
            
            local nodes = {}
            self._outline_nodes[type] = nodes

            local colors = stonehearth_ace.connection_client:get_connection_type_colors(type) or
               stonehearth_ace.connection_client:get_connection_type_colors('default')
            
            if colors then
               for name, connector in pairs(connection.connectors) do
                  if connector.region then   -- the dynamic connectors won't have regions in the component data
                     local color = nil
                     local EDGE_COLOR_ALPHA = 12
                     local FACE_COLOR_ALPHA = 6
                     
                     local connector_data = type_data and type_data.connectors[name]
                     local connector_available = true
                     local connector_connected = false
                     if connector_data then
                        connector_available = connector_data.num_connections < connector_data.max_connections
                        connector_connected = connector_data.num_connections > 0
                     end

                     local is_available = available and connector_available
                     local is_connected = connected and connector_connected
                     if is_available and colors.available_color then
                        color = colors.available_color
                     elseif is_connected and colors.connected_color then
                        color = colors.connected_color
                     end
                     
                     if self._in_selected_graphs and not ignore_hilighting then
                        local hilight_color = colors.graph_hilight_color
                        local hilight_priority = colors.graph_hilight_priority
                        if hilight_color and hilight_priority > hilight.priority then
                           hilight.color = hilight_color
                           hilight.priority = hilight_priority
                        end
                     end
                     
                     -- only render actually available or connected connectors
                     if color and (is_available or is_connected) then
                        local r
                        if radiant.util.is_table(connector.region) then
                           r = Region3()
                           r:load(connector.region)
                        else
                           r = Region3(connector.region)
                        end
                        r:translate(self._origin_offset)
                        
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
         end
      end
   end

   if hilight.color then
      self._is_hilighted = true
      _radiant.client.hilight_entity(self._entity, hilight.color)
   end
end

return ConnectionRenderer
