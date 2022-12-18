local log = radiant.log.create_logger('entity_faction')

local EntityKingdomComponent = class()

function EntityKingdomComponent:initialize()
	local json = radiant.entities.get_json(self)
	-- load up any points/regions/settings we want to store
	if json then
		self._json_values = radiant.shallow_copy(json)
	else
		self._json_values = {}
	end
end

function EntityKingdomComponent:create()
	self._is_create = true
end

function EntityKingdomComponent:post_activate()
	self:_create_listeners()
	self:_set_kingdom(self._entity:get_player_id())

	if self._is_create then
		self:apply_kingdom_modifications()
	end
end

function EntityKingdomComponent:destroy()
	-- shut down listeners
	self:_destroy_listeners()
end

function EntityKingdomComponent:_create_listeners()
	-- start up listener for player_id changes
	-- only need to do this for the server (?)
	if radiant.is_server then
		self._player_id_trace = self._entity:trace_player_id('sync entity forms', _radiant.dm.TraceCategories.SYNC_TRACE)
										:on_changed(function(player_id)
											self:_on_player_id_changed(player_id)
										end)
	end

	-- start up listeners for form changes
	local entity_forms = self._entity:get_component('stonehearth:entity_forms')
	if entity_forms then
		self._ghost_placed_listener = radiant.events.listen(entity_forms, 'stonehearth:entity:ghost_placed', self, self._on_ghost_placed)
	end
end

function EntityKingdomComponent:_destroy_listeners()
	if self._player_id_trace then
		self._player_id_trace:destroy()
		self._player_id_trace = nil
	end

	if self._ghost_placed_listener then
		self._ghost_placed_listener:destroy()
		self._ghost_placed_listener = nil
	end
end

function EntityKingdomComponent:apply_kingdom_modifications()
	-- apply any settings we have for the current kingdom
	local values = (self._kingdom and self._json_values[self._kingdom]) or {}

	-- apply models
	local models = values.models or {}
	self:_apply_models(models.model, models.iconic, models.ghost)

	-- anything else we want to do? effects?
end

function EntityKingdomComponent:_apply_models(model, iconic, ghost)
	local modify = self._entity:add_component('stonehearth_ace:entity_modification')
	if model then
		modify:set_model_variant(model)
	else
		modify:reset_model_variant()
	end

	local entity_forms = self._entity:get_component('stonehearth:entity_forms')
	if entity_forms then
		self._sv.iconic_entity = entity_forms:get_iconic_entity()
		self._sv.iconic_model = iconic
		if self._sv.iconic_entity then
			modify = self._sv.iconic_entity:add_component('stonehearth_ace:entity_modification')
			if iconic then
				modify:set_model_variant(iconic)
			else
				modify:reset_model_variant()
			end
		end

		self._sv.ghost_entity = entity_forms:get_iconic_entity()
		self._sv.ghost_model = ghost
		if self._sv.ghost_entity then
			modify = self._sv.ghost_entity:add_component('stonehearth_ace:entity_modification')
			if ghost then
				modify:set_model_variant(ghost)
			else
				modify:reset_model_variant()
			end
		end

		self.__saved_variables:mark_changed()
	end
end

function EntityKingdomComponent:_set_kingdom(player_id)
	local pop = stonehearth.population:get_population(player_id)
	self._kingdom = pop and pop:get_kingdom()
end

function EntityKingdomComponent:_on_ghost_placed()
	local entity_forms = self._entity:get_component('stonehearth:entity_forms')
	self._sv.ghost_entity = entity_forms:get_ghost_placement_entity()
	if self._sv.ghost_entity and self._sv.ghost_model then
		self._sv.ghost_entity:add_component('stonehearth_ace:entity_modification'):set_model_variant(self._sv.ghost_model)
	end
	self.__saved_variables:mark_changed()
end

function EntityKingdomComponent:_on_player_id_changed(player_id)
	self:_set_kingdom(player_id)
	self:apply_kingdom_modifications()
end

return EntityKingdomComponent