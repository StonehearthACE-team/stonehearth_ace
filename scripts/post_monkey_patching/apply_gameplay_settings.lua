-- this is for sensitive gameplay settings that can't be set through some other service or component loading
-- e.g., if patching or overriding is otherwise impractical

return function()
   -- check the gameplay setting for whether to limit network data
   -- this will always be on the host, and there's no player_id on this entity, so just get it straight from the config
   local limit_data = radiant.util.get_global_config('mods.stonehearth_ace.limit_network_data', true)
   stonehearth.presence:set_limit_network_data(limit_data)
end