local log = radiant.log.create_logger('connection_utils')
local connection_utils = {}

function connection_utils.combine_tables(into, from)
   for k, v in pairs(from) do
      into[k] = v
   end
   return into
end

function connection_utils.combine_type_tables(t1, t2)
   -- this is called with the player-specific and all-players graphs_changed tables
   -- since a connection type is one or the other, we can simply combine all the types found
   -- this may cause issues if people change that property on a connection type in the middle of a game, but they really shouldn't do that
   local t = {}

   for _, copy_from in ipairs({t1, t2}) do
      for type, conns in pairs(copy_from) do
         if not t[type] then
            t[type] = {}
         end
         connection_utils.combine_tables(t[type], conns)
      end
   end

   return t
end

function connection_utils.combine_entity_tables(t1, t2)
   -- this is called with the player-specific and all-players connected_entities tables
   local t = {}
   
   for _, copy_from in ipairs({t1, t2}) do
      for entity, data in pairs(copy_from) do
         if not t[entity] then
            t[entity] = {}
         end
         for type, type_data in pairs(data) do
            if not t[entity][type] then
               t[entity][type] = {}
            end
            t[entity][type].available = type_data.available
            if not t[entity][type].connected_connectors then
               t[entity][type].connected_connectors = {}
            end
            connection_utils.combine_tables(t[entity][type].connected_connectors, type_data.connected_connectors or {})
         end
      end
   end

   return t
end

return connection_utils