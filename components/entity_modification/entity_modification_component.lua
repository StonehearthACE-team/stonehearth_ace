local rng = _radiant.math.get_default_rng()
local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('entity_modification')

local EntityModificationComponent = class()

function EntityModificationComponent:initialize()
	local json = radiant.entities.get_json(self)
	-- load up any points/regions/settings we want to store
	if json and json.values then
		self._json_values = radiant.shallow_copy(json.values)
	else
		self._json_values = {}
	end
end

function EntityModificationComponent:set_region3s(component_name, regions)
	-- if we weren't passed a key to our own values, assume we were passed [an array of] Region3 objects
	regions = self._json_values[regions] or regions
	local region3s = nil
	if regions then
		region3s = {}
		-- first check if it's an array; if not, make it one
		-- can't do a simple table type check because you could be passing in a json region
		if radiant.util.is_a(regions, Cube3) or radiant.util.is_a(regions, Region3)
				or regions.get and type(regions.get) == 'function' then
			regions = { regions }
		end

		for _, r in pairs(regions) do
			if radiant.util.is_a(r, Cube3) then
				table.insert(region3s, Region3(r))
			elseif radiant.util.is_a(r, Region3) then
				table.insert(region3s, r)
			elseif r.get and type(r.get) == 'function' then
				-- assume that this is a a c++ Region3 if it has .get(), rather than having to do the following check:
				-- if radiant.util.typename(r) == 'class radiant::dm::Boxed<class radiant::csg::Region<double,3>,1026>' then
				table.insert(region3s, r:get())
			else
				local cube = radiant.util.to_cube3(r)
				if cube then
					table.insert(region3s, Region3(cube))
				end
			end
		end
	end
	
	if region3s then
		local component = self._entity:add_component(component_name)
		if component then
			component:set_region(_radiant.sim.alloc_region3())
				:get_region():modify(function(cursor)
						for _, r in pairs(region3s) do
							-- does this work? does copy_region just replace all existing regions?
							cursor:copy_region(r)
						end
					end)
		end
	end
end

function EntityModificationComponent:reset_region3s(component_name)
	local json = radiant.entities.get_component_data(self._entity, component_name)
	if json then
		self:set_region3s(component_name, json.region)
	end
end

function EntityModificationComponent:set_region_collision_type(type)
	type = self._json_values[type] or type
	if type and radiant.util.is_string(type) then
		if type:lower() == 'none' then
			type = _radiant.om.RegionCollisionShape.NONE
		elseif type:lower() == 'solid' then
			type = _radiant.om.RegionCollisionShape.SOLID
		elseif type:lower() == 'platform' then
			type = _radiant.om.RegionCollisionShape.PLATFORM
		else
			log:error('unknown region_collision_shape type: %s', type)
			type = nil
		end
	end

	if type then
		self._entity:add_component('region_collision_shape'):set_region_collision_type(type)
	end
end

function EntityModificationComponent:reset_region_collision_type()
	local json = radiant.entities.get_component_data(self._entity, 'region_collision_shape')
	if json then
		self:set_region_collision_type(json.region_collision_type)
	end
end

function EntityModificationComponent:set_movement_modifier_shape_modifier(movement_modifier, nav_preference_modifier)
	movement_modifier = self._json_values[movement_modifier] or movement_modifier
	nav_preference_modifier = self._json_values[nav_preference_modifier] or nav_preference_modifier
	
	local component = self._entity:add_component('movement_modifier_shape')

	if movement_modifier then
		component:set_modifier(movement_modifier)
	end

	if nav_preference_modifier then
		component:set_nav_preference_modifier(nav_preference_modifier)
	end
end

function EntityModificationComponent:reset_movement_modifier_shape_modifier(movement_modifier, nav_preference_modifier)
	local json = radiant.entities.get_component_data(self._entity, 'movement_modifier_shape')
	if json then
		if movement_modifier then
			self:set_modifier(component_name, json.modifier)
		end
		if movement_modifier then
			self:set_nav_preference_modifier(component_name, json.nav_preference_modifier)
		end
	end
end

function EntityModificationComponent:set_model_variant(model_variant, override_original)
	local component = self._entity:add_component('render_info')
	if component then
		local current_model_variant = component:get_model_variant()
		-- always default to our key if present
		model_variant = self._json_values[model_variant] or model_variant
		
		-- check if the model_variant (our key) is actually an array of variants
		-- if so, check if it specified a type of 'one_of'
		-- if so, choose a random variant from the array
		-- otherwise, check if the current model is in the list
		-- if so, choose the next model in the sequence, looping around to start; otherwise, choose the first model
		if model_variant.models and type(model_variant.models) == 'table' and #model_variant.models > 0 then
			local index = 1
			if model_variant.type == 'one_of' then
				index = rng:get_int(1, #model_variant.models)
			else
				-- see if the current model is in this list; if so, get the next entry
				for i = 1, #model_variant.models do
					if model_variant.models[i] == current_model_variant then
						index = (i % #model_variant.models) + 1
						break
					end
				end
			end
			log:debug('setting model_variant to index %d (of %d): %s', index, #model_variant.models, model_variant.models[index])
			model_variant = model_variant.models[index]
		end

		if model_variant and model_variant ~= current_model_variant then
			-- for this one we want to back up the original/previous model_variant for resetting
			-- since it could've been a random 'one_of'; but only back it up if it's the original (or we specify to override)
			-- unfortunately render_info doesn't give us the specific current model_variant, so we can only reliably back up after our first change
			if not self._sv.original_model_variant or override_original then
				self._sv.original_model_variant = current_model_variant
			end

			self.__saved_variables:mark_changed()

			component:set_model_variant(model_variant)
		end
	end
end

function EntityModificationComponent:reset_model_variant()
	local component = self._entity:add_component('render_info')
	if component then
		local model_variant = self._sv.original_model_variant
		if model_variant then
			component:set_model_variant(model_variant)
			-- once we've 'reset', whatever model_variant was stored is considered the new original
			-- so we don't need to store it unless/until it gets set again
			self._sv.original_model_variant = nil
			self.__saved_variables:mark_changed()
		end
	end
end

return EntityModificationComponent
