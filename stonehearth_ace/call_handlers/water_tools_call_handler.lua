local validator = radiant.validator
local log = radiant.log.create_logger('water_tools')

local WaterToolsCallHandler = class()

function WaterToolsCallHandler:toggle_water_gate_command(session, response, water_gate, old_command, new_command)
	validator.expect_argument_types({'Entity', 'string', 'string'}, water_gate, old_command, new_command)
	validator.expect.matching_player_id(session.player_id, water_gate)
	
	-- original enabled status would be doing true == 1, but we want to negate it because we're toggling it
	local enabled = radiant.entities.get_attribute(water_gate, 'enabled', 0) == 0
	local region_collision_shape = water_gate:get_component('region_collision_shape')
	local new_collision_type
	if enabled then
		new_collision_type = _radiant.om.RegionCollisionShape.PLATFORM
	else
		new_collision_type = _radiant.om.RegionCollisionShape.SOLID
	end

	if region_collision_shape then
		radiant.entities.set_attribute(water_gate, 'enabled', enabled and 1 or 0)
		region_collision_shape:set_region_collision_type(new_collision_type)

		-- swap commands
		local commands_component = water_gate:get_component('stonehearth:commands')
		if commands_component then
			commands_component:remove_command(old_command)
			commands_component:add_command(new_command)
		end

		-- do anything else here like playing animations?

		radiant.events.trigger(radiant, 'stonehearth_ace:on_water_gate_toggled', { water_gate = water_gate, enabled = enabled })
		return true
	end

	return false
end

return WaterToolsCallHandler