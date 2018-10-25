--[[
connection json structure:
connector regions are typically a 2-voxel region, including one voxel inside the entity and another outside it
"stonehearth_ace:connection": {
   "type1": {
      "connectors": {
         "connector1": {
            "region": {
               "min": { "x": -1, "y": 0, "z": 0 },
               "max": { "x": 1, "y": 1, "z": 1 }
            },
            "max_connections": 1,
            "region_intersection_threshold": 1
         },
         "connector2": {
            "region": {
               "min": { "x": 0, "y": 0, "z": 0 },
               "max": { "x": 2, "y": 1, "z": 1 }
            },
            "max_connections": 1
         }
      },
      "max_connections": 1
   }
}
]]
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
   stonehearth_ace.connection:register_entity(self._entity, self._connections)
   -- also need to set up a listener in case this entity changes ownership to then unregister it and re-register it
end

function ConnectionComponent:destroy()
   stonehearth_ace.connection:unregister_entity(self._entity)
end

function ConnectionComponent:_format_connections()
   for type, connections in pairs(self._connections) do
      for name, connector in pairs(connections.connectors) do
         -- transform all the region JSON data into Cube3 structures
         -- TODO: since this is a cached table, this really only needs to happen once; simple type check? does it matter?
         connector.region = radiant.util.to_cube3(connector.region)
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
   for type, type_stats in pairs(stats) do
      local these_stats = self._sv.connected_stats[type]
      if not these_stats then
         these_stats = {connected_connectors = {}}
         self._sv.connected_stats[type] = these_stats
      end
      if type_stats.available ~= nil then
         these_stats.available = type_stats.available
      end
      
      if type_stats.connected_connectors then
         for id, connected in pairs(type_stats.connected_connectors) do
            these_stats.connected_connectors[id] = connected or nil
         end
      end
   end
   
   self.__saved_variables:mark_changed()
end

return ConnectionComponent