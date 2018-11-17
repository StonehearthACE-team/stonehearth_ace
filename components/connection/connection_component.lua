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

function ConnectionComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._connections = json or {}
   self:_format_connections()
   self._sv.connected_stats = {}
end

-- this is performed in activate rather than post_activate so that all specific connection services can use it in post_activate
function ConnectionComponent:activate()
   if radiant.is_server then
      stonehearth_ace.connection:register_entity(self._entity, self._connections)
   end
end

function ConnectionComponent:destroy()
   if radiant.is_server then
      stonehearth_ace.connection:unregister_entity(self._entity)
   end
end

function ConnectionComponent:_format_connections()
   for _, connections in pairs(self._connections) do
      for _, connector in pairs(connections.connectors) do
         -- transform all the region JSON data into Cube3 structures
         -- since this is a cached table, this really only needs to happen once; simple type check?
         if type(connector.region) == 'table' then
            connector.region = import_region(connector.region)
            connector.region:optimize('connector region')
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

-- this is called by the connection service when this entity has any of its connectors change status
function ConnectionComponent:set_connected_stats(stats)
   _update_entity_connection_data(self._sv.connected_stats, stats)
   self.__saved_variables:mark_changed()
end

return ConnectionComponent