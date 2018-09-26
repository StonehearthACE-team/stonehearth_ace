local validator = radiant.validator
local log = radiant.log.create_logger('toggle_training')

local ToggleTrainingCallHandler = class()

function ToggleTrainingCallHandler:toggle_training_command(session, response, entity, enabled)
	validator.expect_argument_types({'Entity'}, entity)
	validator.expect.matching_player_id(session.player_id, entity)
	
	local job = entity:get_component('stonehearth:job')
	if job then
		job:toggle_training(enabled)
	end
end

return ToggleTrainingCallHandler