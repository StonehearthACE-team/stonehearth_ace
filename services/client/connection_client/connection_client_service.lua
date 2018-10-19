--[[
   this service listens for relevant changes to the server connection service
   used for: render colors for connection types
]]

local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('connection_client')
local ConnectionClientService = class()

function ConnectionClientService:initialize()
   self._connection_colors = {}
   self._connections = {}

   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
      self:_setup_connection_types()
      _radiant.call_obj('stonehearth_ace.connection', 'get_connections_datastore_command')
         :done(function (response)
            local connections = response.connections
            self._connections_trace = connections:trace_data('client connections')
            :on_changed(function()
                  self._connections = connections:get_data()
               end)
            :push_object_state()
         end)
      end)
end

function ConnectionClientService:destroy()
   self:destroy_listeners()
end

function ConnectionClientService:destroy_listeners()
   if self._connections_listener then
      self._connections_listener:destroy()
      self._connections_listener = nil
   end
   if self._connections_trace then
      self._connections_trace:destroy()
      self._connections_trace = nil
   end
end

function ConnectionClientService:_setup_connection_types()
   _radiant.call_obj('stonehearth_ace.connection', 'get_connection_types_command')
      :done(function(response)
         for name, type in pairs(response.types) do
            local colors = {}
            colors.connected = Point3(unpack(type.connected_color)) or Point3(64, 240, 0)
            colors.disconnected = Point3(unpack(type.disconnected_color)) or Point3(colors.connected.x / 2, colors.connected.y / 2, colors.connected.z / 2)

            self._connection_colors[name] = colors
         end
      end)
end

function ConnectionClientService:get_connection_type_colors(type)
   return self._connection_colors[type]
end

function ConnectionClientService:is_connector_connected(type, entity_id, connector_id)
   -- look it up in the _connections table; if it's not there, assume it's disconnected
   local connections = self._connections[type]
   return connections and connections[entity_id..'|'..connector_id]
end

return ConnectionClientService