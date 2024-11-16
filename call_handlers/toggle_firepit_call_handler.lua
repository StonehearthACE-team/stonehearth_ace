local validator = radiant.validator
local log = radiant.log.create_logger('toggle_firepit')

local ToggleFirepitCallHandler = class()

function ToggleFirepitCallHandler:toggle_firepit_command(session, response, entity, enabled)
	validator.expect_argument_types({'Entity'}, entity)
	validator.expect.matching_player_id(session.player_id, entity)
	
	local lamp_component = entity:get_component('stonehearth:lamp')
	local firepit_component = entity:get_component('stonehearth:firepit')
	local commands_component = entity:add_component('stonehearth:commands')

	if lamp_component and firepit_component and commands_component then
		if enabled then
			lamp_component:set_light_policy('manual')
			firepit_component:_start_or_stop_firepit()
			commands_component:remove_command('stonehearth_ace:commands:toggle_firepit_on')
			commands_component:add_command('stonehearth_ace:commands:toggle_firepit_off')
		else
			lamp_component:set_light_policy('never')
			firepit_component:_start_or_stop_firepit()
			commands_component:remove_command('stonehearth_ace:commands:toggle_firepit_off')
			commands_component:add_command('stonehearth_ace:commands:toggle_firepit_on')
		end
	end
end

return ToggleFirepitCallHandler