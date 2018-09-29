--[[
   the service mostly just manages the controllers for player connections (similar to the inventory service)
   and allows entities to easily be registered or unregistered
   since this service separates entities by player, entities owned by different players will not "connect" to one another
]]

local PlayerConnections = require 'services.server.connection.player_connections'

local ConnectionService = class()

-- using a local cache for these just like the inventory uses
-- mods that make use of this might make frequent calls here, and it's very little overhead
local CONNECTIONS_BY_PLAYER_ID = {}

function ConnectionService:initialize()
   self._sv = self.__saved_variables:get_data()
   if not self._sv.connections then
      -- First time around.
      self._sv.connections = {}
   else
      -- Reloading. Copy existing data into the cache.
      for k, v in pairs(self._sv.connections) do
         CONNECTIONS_BY_PLAYER_ID[k] = v
      end
   end
end

function ConnectionService:register_entity(entity)
   -- register this entity with the proper player's connections
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)

   player_connections:register_entity(entity)
end

function ConnectionService:unregister_entity(entity)
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)

   player_connections:unregister_entity(entity)
end

function ConnectionService:get_player_connections(player_id)
   local connections = rawget(CONNECTIONS_BY_PLAYER_ID, player_id)
   
   if not connections then
      connections = radiant.create_controller('stonehearth_ace:player_connections', player_id)
      CONNECTIONS_BY_PLAYER_ID[player_id] = connections
      self._sv.connections[player_id] = connections
      self.__saved_variables:mark_changed()
   end

   return connections
end

return ConnectionService