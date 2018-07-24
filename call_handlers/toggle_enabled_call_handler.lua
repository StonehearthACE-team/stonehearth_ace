local validator = radiant.validator
local log = radiant.log.create_logger('toggle_enabled')

local ToggleEnabledCallHandler = class()

function ToggleEnabledCallHandler:toggle_enabled_command(session, response, entity, enabled)
	validator.expect_argument_types({'Entity'}, entity)
	validator.expect.matching_player_id(session.player_id, entity)
	
	local toggle_enabled = entity:get_component('stonehearth_ace:toggle_enabled')
	if toggle_enabled then
		local new_enabled = enabled
		if new_enabled == nil then
			new_enabled = not toggle_enabled:get_enabled()
		end
		toggle_enabled:set_enabled(new_enabled)
	end
end

return ToggleEnabledCallHandler