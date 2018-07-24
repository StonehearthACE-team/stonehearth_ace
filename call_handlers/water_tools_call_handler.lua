local validator = radiant.validator
local log = radiant.log.create_logger('water_tools')

local WaterToolsCallHandler = class()

function WaterToolsCallHandler:toggle_water_tools_command(session, response, entity, enabled)
	validator.expect_argument_types({'Entity'}, entity)
	validator.expect.matching_player_id(session.player_id, entity)
	
	local water_tools = entity:get_component('stonehearth_ace:water_tools')
	if water_tools then
		local new_enabled = enabled
		if new_enabled == nil then
			new_enabled = not water_tools:get_enabled()
		end
		water_tools:set_enabled(new_enabled)
	end
end

return WaterToolsCallHandler