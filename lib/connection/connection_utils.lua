local log = radiant.log.create_logger('connection_utils')
local connection_utils = {}

function connection_utils.combine_tables(into, from)
   for k, v in pairs(from) do
      into[k] = v
   end
   return into
end

function connection_utils.combine_type_tables(t1, t2)
   -- this is called with the player-specific and all-players connections and graphs_changed tables
   -- since a connection type is one or the other, we can simply combine all the types found
   -- this may cause issues if people change that property on a connection type in the middle of a game, but they really shouldn't do that
   local t = {}
   for type, conns in pairs(t1) do
      if not t[type] then
         t[type] = {}
      end
      connection_utils.combine_tables(t[type], conns)
   end
   for type, conns in pairs(t2) do
      if not t[type] then
         t[type] = {}
      end
      connection_utils.combine_tables(t[type], conns)
   end

   return t
end

return connection_utils