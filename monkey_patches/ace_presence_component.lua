local PresenceComponent = require 'stonehearth.components.presence.presence_component'
local AcePresenceComponent = class()

AcePresenceComponent._ace_old_activate = PresenceComponent.activate
function AcePresenceComponent:activate()
   self:_ace_old_activate()

   -- check the gameplay setting for whether to limit network data
   -- this will always be on the host, and there's no player_id on this entity, so just get it straight from the config
   local limit_data = radiant.util.get_global_config('mods.stonehearth_ace.limit_network_data', true)
   self:set_limit_network_data(limit_data)
end

-- this will get called by the settings_call_handler whenever the setting is changed
function AcePresenceComponent:set_limit_network_data(limit_data)
   self._sv.limit_data = limit_data
   self.__saved_variables:mark_changed()
end

return AcePresenceComponent
