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
   self._connected_entities = {}

   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
      self:_setup_connection_types()
      _radiant.call_obj('stonehearth_ace.connection', 'get_connections_datastore_command')
         :done(function (response)
            local connections = response.connections
            self._connections_trace = connections:trace_data('client connections')
            :on_changed(function()
                  self:_update_connections(connections:get_data())
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

function ConnectionClientService:_update_connections(connection_data)
   local connected_entities = connection_data.connected_entities or {}
   local changed_entities = {}
   for id, _ in pairs(connected_entities) do
      changed_entities[id] = true
   end

   for prev_connected, _ in pairs(self._connected_entities) do
      changed_entities[prev_connected] = not changed_entities[prev_connected]
   end

   self._connections = connection_data.connections or {}
   self._connected_entities = connected_entities

   for e, _ in pairs(changed_entities) do
      --log:debug('triggering entity_updated event for %s', e)
      -- this is used by the connection_renderer to know that connections have been updated and they need to be redrawn
      radiant.events.trigger(e, 'stonehearth_ace:connections:entity_updated')
   end
end

function ConnectionClientService:get_connection_type_colors(type)
   return self._connection_colors[type]
end

function ConnectionClientService:is_connector_connected(type, entity_id, connector_id)
   -- look it up in the _connections table; if it's not there, assume it's disconnected
   local connections = self._connections[type]
   return connections and connections[entity_id..'|'..connector_id]
end

function ConnectionClientService:is_entity_connected(entity_id)
   return self._connected_entities[entity_id]
end

return ConnectionClientService