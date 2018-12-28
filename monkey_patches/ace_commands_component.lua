local log = radiant.log.create_logger('commands')

local CommandsComponent = require 'stonehearth.components.commands.commands_component'

local AceCommandsComponent = class()

function AceCommandsComponent:is_command_enabled(uri)
   local command = self._sv.commands[uri]
   return command and command.enabled and not self._sv.disabled
end

return AceCommandsComponent
