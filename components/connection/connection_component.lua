--[[
connection json structure:
connector regions are typically a 2-voxel region, including one voxel inside the entity and another outside it
"stonehearth_ace:connection": {
   "type1": {
      "connectors": {
         "connector1": {
            "region": [
               {
                  "min": { "x": -1, "y": 0, "z": 0 },
                  "max": { "x": 1, "y": 1, "z": 1 }
               }
            ],
            "max_connections": 1,
            "region_intersection_threshold": 1
         },
         "connector2": {
            "region": [
               {
                  "min": { "x": 0, "y": 0, "z": 0 },
                  "max": { "x": 2, "y": 1, "z": 1 }
               }
            ],
            "max_connections": 1
         }
      },
      "max_connections": 1
   }
}
]]
local ConnectionUtils = require 'lib.connection.connection_utils'
local _update_entity_connection_data = ConnectionUtils._update_entity_connection_data
local import_region = ConnectionUtils.import_region

local log = radiant.log.create_logger('connection_component')
local ConnectionComponent = class()

local VERSIONS = {
   ZERO = 0,
   V1 = 1,
   V2 = 2,
   V3 = 3
}

function ConnectionComponent:get_version()
   return VERSIONS.V3
end

function ConnectionComponent:fixup_post_load(old_save_data)
   -- just nuke the connected stats and let it automatically rebuild connections
   if old_save_data.version < VERSIONS.V3 then
      self._sv.connected_stats = {}
   end
end

function ConnectionComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._connections = json or {}
   self:_format_connections()
   self._sv.connected_stats = {}
end

function ConnectionComponent:create()
   --self._sv.version = self:get_version()
end

function ConnectionComponent:restore()
   self._is_restore = true
end

-- this is performed in activate rather than post_activate so that all specific connection services can use it in post_activate
function ConnectionComponent:activate()
   local connected_stats
   if self._is_restore and next(self._sv.connected_stats) then
      connected_stats = self._sv.connected_stats
   end

   stonehearth_ace.connection:register_entity(self._entity, self._connections, connected_stats)
end

function ConnectionComponent:destroy()
   stonehearth_ace.connection:unregister_entity(self._entity)
end

function ConnectionComponent:_format_connections()
   for _, connections in pairs(self._connections) do
      for _, connector in pairs(connections.connectors) do
         -- transform all the region JSON data into Cube3 structures
         -- since this is a cached table, this really only needs to happen once; simple type check?
         if type(connector.region) == 'table' then
            connector.region = import_region(connector.region)
            connector.region:optimize('connector region')
         else
            return
         end
      end
   end
end

function ConnectionComponent:get_connections(type)
   if type then
      return self._connections[type]
   else
      return self._connections
   end
end

function ConnectionComponent:get_connected_stats(type)
   local type_data = {}

   for conn_type, data in pairs(self._sv.connected_stats) do
      if not type or conn_type == type then
         _update_entity_connection_data(type_data, { [type] = data })
      end
   end

   -- return nil if no connected stats
   return next(type_data) and type_data
end

-- this is called by the connection service when this entity has any of its connectors change status
-- it may be called with just the type and conn_name to initialize the data structures
-- it may be called with just the type and the graph_id when it changes graphs and needs all connectors for that type to update graph_id
function ConnectionComponent:set_connected_stats(type, conn_name, connected_to_id, graph_id, threshold)
   --log:debug('[%s]:set_connected_stats(%s, %s, %s, %s, %s)', self._entity, type, conn_name or 'NIL', connected_to_id or 'NIL', graph_id or 'NIL', threshold or 'NIL')
   local type_data = self._sv.connected_stats[type]
   if not type_data then
      type_data = {connectors = {}, num_connections = 0, max_connections = self._connections[type].max_connections}
      self._sv.connected_stats[type] = type_data
   end

   if conn_name then
      local conn_data = type_data.connectors[conn_name]
      if not conn_data then
         conn_data = {connected_to = {}, num_connections = 0, max_connections = self._connections[type].connectors[conn_name].max_connections}
         type_data.connectors[conn_name] = conn_data
      end

      if connected_to_id then
         local new_status = (graph_id ~= nil)
         local prev_status = conn_data.connected_to[connected_to_id]
         conn_data.connected_to[connected_to_id] = graph_id and {graph_id = graph_id, threshold = threshold or prev_status.threshold}
         if (prev_status ~= nil) ~= new_status then
            local conn_modifier = (new_status and 1) or -1
            conn_data.num_connections = conn_data.num_connections + conn_modifier
            type_data.num_connections = type_data.num_connections + conn_modifier
         end
      end
   elseif graph_id then
      for name, connector in pairs(type_data.connectors) do
         for id, prev_status in pairs(connector.connected_to) do
            threshold = threshold or 0
            if radiant.util.is_a(prev_status, 'table') then
               threshold = prev_status.threshold
            end
            connector.connected_to[id] = {graph_id = graph_id, threshold = threshold}
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function ConnectionComponent:trace_data(reason)
   return self.__saved_variables:trace_data(reason)
end

return ConnectionComponent