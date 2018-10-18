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
            "region_intersection_threshold": 1,
            "info": {}
         },
         "connector2": {
            "region": {
               "min": { "x": 0, "y": 0, "z": 0 },
               "max": { "x": 2, "y": 1, "z": 1 }
            },
            "max_connections": 1,
            "info": {}
         }
      },
      "max_connections": 1
   }
}
]]

local ConnectionComponent = class()

function ConnectionComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._connections = json or {}
   self:_format_connections()
end

-- this is performed in activate rather than post_activate so that all specific connection services can use it in post_activate
function ConnectionComponent:activate()
   stonehearth_ace.connection:register_entity(self._entity, self._connections)
end

function ConnectionComponent:destroy()
   stonehearth_ace.connection:unregister_entity(self._entity)
end

function ConnectionComponent:_format_connections()
   for type, connections in pairs(self._connections) do
      for name, connector in pairs(connections.connectors) do
         -- transform all the region JSON data into Cube3 structures
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

return ConnectionComponent