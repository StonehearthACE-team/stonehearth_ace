local entity_forms = require 'lib.entity_forms.entity_forms_lib'
local build_util = require 'lib.build_util'

local BuildService = radiant.mods.require('stonehearth.services.server.build.build_service')
local AceBuildService = class()

AceBuildService._old_erase_fixture = BuildService.erase_fixture
AceBuildService._old_add_fixture = BuildService.add_fixture

function AceBuildService:erase_fixture(fixture_blueprint)
	-- grab the parent before we unlink, since the unlinking process will remove
	-- the entity from the world
	local parent = radiant.entities.get_parent(fixture_blueprint)

	-- if we're removing the fixture from a wall, just use the old function
	if parent and parent:get_component('stonehearth:wall') then
		self:_old_erase_fixture(fixture_blueprint)
		return
	end
   
	self:unlink_entity(fixture_blueprint)

	-- if we're a hatch and were taken off a floor, re-layout to clear the hole.
	if parent then
		local floor = parent:get_component('stonehearth:floor')
		if floor then
			floor:remove_fixture(fixture_blueprint)
					:layout()
		end
	end
end

function AceBuildService:add_fixture(parent_entity, fixture_or_uri, quality, location, normal, rotation, opt_fixture_ghost)
	-- if we're adding the fixture to a wall, just use the old function
	if parent_entity:get_component('stonehearth:wall') then
		self:_old_add_fixture(parent_entity, fixture_or_uri, quality, location, normal, rotation, opt_fixture_ghost)
		return
	end
   
	if not build_util.is_blueprint(parent_entity) then
		self._log:info('cannot place fixture %s on non-blueprint entity %s', fixture_or_uri, parent_entity)
		return
	end

	local always_show_ghost = build_util.blueprint_is_finished(parent_entity)

	if not normal then
		normal = parent_entity:get_component('stonehearth:construction_data')
								:get_normal()
	end
	assert(normal)

	local _, fixture_blueprint

	local _, _, fixture_ghost_uri = entity_forms.get_uris(fixture_or_uri)
	fixture_blueprint = radiant.entities.create_entity(fixture_ghost_uri, {
			owner = parent_entity,
			debug_text = 'fixture blueprint',
		})

	local building = build_util.get_building_for(parent_entity)

	self:_bind_building_to_blueprint(building, fixture_blueprint)

	local floor = parent_entity:get_component('stonehearth:floor')
	if floor then
		-- add the new fixture to the floor and reconstruct the shape.
		floor:add_fixture(fixture_blueprint, location, normal)
				:layout()
	else
		radiant.entities.add_child(parent_entity, fixture_blueprint, location)
		radiant.entities.turn_to(fixture_blueprint, rotation or 0)
	end

	self:add_fixture_fabricator(fixture_blueprint, fixture_or_uri, quality, normal, rotation, always_show_ghost, opt_fixture_ghost)

	-- fixtures can be added to the building after it's already been started.
	-- if this is the case, go ahead and start the placing process
	local active = building:get_component('stonehearth:construction_progress')
								:get_active()
	if active then
		fixture_blueprint:get_component('stonehearth:construction_progress')
							:set_active(true)
	end
	return fixture_blueprint
end

return AceBuildService
