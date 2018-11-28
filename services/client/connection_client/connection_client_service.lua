--[[
   this service listens for relevant changes to the server connection service
   used for: render colors for connection types
]]

local Point3 = _radiant.csg.Point3
local ConnectionUtils = require 'lib.connection.connection_utils'

local combine_tables = ConnectionUtils.combine_tables
local combine_type_tables = ConnectionUtils.combine_type_tables

local log = radiant.log.create_logger('connection_client')

local ConnectionClientService = class()

function ConnectionClientService:initialize()
   self._connection_colors = {}
   self._connections = {}
   self._last_selected = {}

   self:_setup_connection_types()

   self._selection_changed_listener = radiant.events.listen(radiant, 'stonehearth:selection_changed', self, self._on_selection_changed)
end

function ConnectionClientService:destroy()
   self:destroy_listeners()
end

function ConnectionClientService:destroy_listeners()
   if self._connections_trace then
      self._connections_trace:destroy()
      self._connections_trace = nil
   end
end

function ConnectionClientService:_on_selection_changed()
   local selected = stonehearth.selection:get_selected()
   local selected_id = selected and selected:get_id()
   _radiant.call_obj('stonehearth_ace.connection', 'get_entities_in_selected_graphs_command', selected_id)
      :done(function(response)
         local diff = {}
         for id, _ in pairs(response.entities) do
            if not self._last_selected[id] then
               diff[id] = true
            end
         end
         for id, _ in pairs(self._last_selected) do
            if not response.entities[id] then
               diff[id] = false
            end
         end
         if selected_id then
            diff[selected_id] = nil
         end
         self._last_selected = response.entities

         for id, in_selected_graphs in pairs(diff) do
            local entity = radiant.entities.get_entity(tonumber(id))
            radiant.events.trigger(entity, 'stonehearth_ace:entity_in_selected_graphs_changed', in_selected_graphs)
         end
      end)
end

function ConnectionClientService:update_client_connections()
   _radiant.call_obj('stonehearth_ace.connection', 'get_connections_data_command')
      :done(function (response)
         self._connections = response.connections
      end)
end

function ConnectionClientService:_setup_connection_types()
   _radiant.call_obj('stonehearth_ace.connection', 'get_connection_types_command')
      :done(function(response)
         for name, type in pairs(response.types) do
            local colors = {}
            if type.available_color then
               colors.available_color = Point3(unpack(type.available_color))
            end
            if type.connected_color then
               colors.connected_color = Point3(unpack(type.connected_color))
            end
            if type.graph_hilight_color then
               colors.graph_hilight_color = Point3(unpack(type.graph_hilight_color))
            end
            colors.graph_hilight_priority = type.graph_hilight_priority or 0

            self._connection_colors[name] = colors
         end
      end)
end

function ConnectionClientService:get_connection_type_colors(type)
   return self._connection_colors[type]
end

function ConnectionClientService:get_entity_connection_stats(entity_id)
   return self._connections[tostring(entity_id)] or {}
end

return ConnectionClientService