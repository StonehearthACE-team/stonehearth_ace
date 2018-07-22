-- do we even need this component? maybe we can do it all with ai actions/packs and leases
-- and then just have the training data for the training spot child entity in its 'entity_data'

-- however, we do need the component, not for the individual training spots, but for the training entity
-- so it can create and manage the spots as child entities

-- maybe instead of manually specifying all training spots in the json, we can dynamically create them
-- when there's a request from a soldier to train here, and just specify the max soldiers that can train here at once

local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local combat = stonehearth.combat

local TrainingComponent = class()

function TrainingComponent:initialize()
	self._json = entities.get_json(self) or {}
end

function TrainingComponent:create()
	self._is_create = true
end

function TrainingComponent:post_activate()
	if self._is_create then
		self._sv.enabled = self._json.enabled or false
		self:_startup()
	end
end

function TrainingComponent:destroy()
	self:_shutdown()
end

function TrainingComponent:set_enabled(enabled)
	if self._sv.enabled ~= enabled then
		self._sv.enabled = enabled
		if enabled then
			self:_startup()
		else
			self:_shutdown()
		end

		self.__saved_variables:mark_changed()
	end
end

function TrainingComponent:train_here(entity)
	if self._sv.enabled and #self._sv.positions < self._sv.max_positions then
		self:_create_training_position(entity)
		return true
	end

	return false
end

function TrainingComponent:_startup()
	-- load training positions
	self._sv.positions = {}
	self._sv.max_positions = self._json.positions or 1
	self.__saved_variables:mark_changed()
end

function TrainingComponent:_shutdown()
	-- if there were any soldiers training here, tell them to rethink their task?
	-- then delete the child entities
	for _, position in ipairs(self._sv.positions) do
		
	end
	self._sv.position
end

function TrainingComponent:_create_training_position(entity)
	-- stonehearth.combat (service) has useful functions like:
	--	get_main_weapon(entity)
	--	local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
	--	get_melee_range(attacker, weapon_data, target)
	--	get_weapon_range(attacker, weapon)
	--	maybe get_combat_state(entity) and set_stance(entity, stance)

	local weapon = combat:get_main_weapon(entity)
	local weapon_data = combat:get_main_weapon(entity)
	local range
	if weapon_data.range then
		-- it's a ranged combat class so get the range including any bonus range
		range = combat:get_weapon_range(entity, weapon)
	else
		-- otherwise it's melee so get the reach
		range = get_melee_range(entity, weapon_data, self._entity)
	end

	-- try to find a good spot for the training position that's in front of it and has line of sight

end

return TrainingComponent