local validator = radiant.validator
local log = radiant.log.create_logger('water_tools')

local WaterToolsCallHandler = class()

function WaterToolsCallHandler:toggle_water_gate_command(session, response, water_gate)
	local selected = stonehearth.selection:get_selected()
	
	_radiant.call('stonehearth_ace:toggle_water_gate', water_gate)
		:done(function(result)
			local new_water_gate = result.new_water_gate

			if selected == water_gate and new_water_gate then
				stonehearth.selection:select_entity(new_water_gate)
			end
		end)
end

function WaterToolsCallHandler:toggle_water_gate(session, response, water_gate)
	validator.expect_argument_types({'Entity'}, water_gate)
	validator.expect.matching_player_id(session.player_id, water_gate)

	-- code below largely copied and modified from evolve_component.lua > EvolveComponent:evolve()
	local location = radiant.entities.get_world_grid_location(water_gate)
	if not location then
		response:resolve({})
		return
	end
	local facing = radiant.entities.get_facing(water_gate)

	local modes = radiant.entities.get_entity_data(water_gate, 'stonehearth_ace:engineering:modes')
	local toggle = modes.toggle
	if not toggle then
		response:resolve({})
		return
	end
	--Create the evolved entity and put it on the ground
	local new_water_gate = radiant.entities.create_entity(toggle, { owner = water_gate})
	local new_modes = radiant.entities.get_entity_data(new_water_gate, 'stonehearth_ace:engineering:modes')

	-- Have to remove entity because it can collide with evolved form
	radiant.terrain.remove_entity(water_gate)
	if not radiant.terrain.is_standable(new_water_gate, location) then
		-- If cannot evolve because the evolved form will not fit in the current location, reset it.
		radiant.terrain.place_entity_at_exact_location(water_gate, location, { force_iconic = false, facing = facing })
		radiant.entities.destroy_entity(new_water_gate)
		response:resolve({})
		return
	end

	radiant.terrain.place_entity_at_exact_location(new_water_gate, location, { force_iconic = false, facing = facing } )

	radiant.events.trigger(radiant, 'stonehearth_ace:on_water_gate_toggled',
							{ old_water_gate = water_gate, new_water_gate = new_water_gate, new_mode = new_modes.current_mode })
	radiant.entities.destroy_entity(water_gate)

	response:resolve({new_water_gate = new_water_gate})
end

return WaterToolsCallHandler