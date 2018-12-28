local FoodDecayService = require 'stonehearth.services.server.food_decay.food_decay_service'
AceFoodDecayService = class()

function AceFoodDecayService:initialize()
   self.food_type_tags = {"raw_food", "prepared_food", "luxury_food"}
   self.enable_decay = true
   self._sv = self.__saved_variables:get_data()
   if not self._sv.initialized then
      self._sv.initialized = true
      self._sv._decaying_food = {}
      self._sv.decay_listener = stonehearth.calendar:set_persistent_interval("FoodDecayService on_decay", '1h', function()
            self:_on_decay()
         end)
      self._sv.food_type_counts = {}
      self._sv.version = self:get_version()
   else
      -- fix up food decay not having decay value
      self._sv.version = self._sv.version or VERSIONS.ZERO
      if self._sv.version ~= self:get_version() then
         self:fixup_post_load()
      end

      self._sv.decay_listener:bind(function()
         self:_on_decay()
      end)
   end

   self._decay_per_hour = stonehearth.constants.food_decay.DEFAULT_DECAY_PER_HOUR

   local entity_container = radiant.events.listen(radiant, 'radiant:entity:post_create', function(e)
            local entity = e.entity
            self:_on_entity_added_to_world(entity)
         end)

   radiant.events.listen(radiant, 'radiant:entity:post_destroy', function(e)
         local entity_id = e.entity_id
         self:_on_entity_destroyed(entity_id)
      end)

   self._post_create_listener = radiant.events.listen(radiant, 'radiant:entity:post_create', function(e)
      local entity = e.entity
      self:_on_entity_added_to_world(entity)
   end)

   self._biome_initialized_listener = radiant.events.listen(stonehearth.world_generation, 'stonehearth:world_generation:biome_initialized', function(e)
         self:_update_decay_per_hour()
      end)

   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
         if self._post_create_listener then
            self._post_create_listener:destroy()
            self._post_create_listener = nil
         end
         if not stonehearth.calendar:is_tracking_timer(self._sv.decay_listener) then
            radiant.log.write('food_decay', 0, 'food decay does not have a listener tracked by the calendar. Recreating a listener')
            if self._sv.decay_listener then
               self._sv.decay_listener:destroy()
            end
            -- omg there was a save file where this listener was lost too? I am le sad. -yshan
            self._sv.decay_listener = stonehearth.calendar:set_persistent_interval("FoodDecayService on_decay", '1h', function()
                  self:_on_decay()
               end)
         end
         self._game_loaded_listener = nil
      end)
end

function AceFoodDecayService:increment_decay(food_decay_data)
   local entity = food_decay_data.entity
   local inventory = nil
   local location = nil
   local player_id = radiant.entities.get_player_id(entity)

   local decay_tuning = food_decay_data.decay_tuning
   local initial_decay = food_decay_data.decay
   local decay = initial_decay - self._decay_per_hour;
   food_decay_data.decay = decay
   if decay <= 0 then
		inventory = stonehearth.inventory:get_inventory(player_id)
		location = radiant.entities.get_world_grid_location(entity)
		if not location then
            local storage = inventory:container_for(entity)
            if storage then
			self:_convert_to_rotten_form(entity, decay_tuning.rotten_entity_alias)
			end
		else
		self:_convert_to_rotten_form(entity, decay_tuning.rotten_entity_alias)
		end
	elseif decay_tuning.decay_stages then
      -- Figure out if we're supposed to be in some other model state

      local new_decay_stage = nil
      local lowest_trigger_value = initial_decay + 1
      local effect = nil
      for _, decay_stage in pairs(decay_tuning.decay_stages) do
         -- Find the decay stage most suited for our decay value.
         -- Unfortunately this means iterating through all the stages,
         -- but there should only be 2 stages or so.
         if decay <= decay_stage.trigger_decay_value and decay_stage.trigger_decay_value < lowest_trigger_value then
            lowest_trigger_value = decay_stage.trigger_decay_value
            new_decay_stage = decay_stage
         end
      end
      if new_decay_stage then
         if new_decay_stage.description then
            radiant.entities.set_description(entity, new_decay_stage.description)
         end
         if new_decay_stage.model_variant then
            entity:get_component('render_info'):set_model_variant(new_decay_stage.model_variant)
         end
      end
   end
   return true
end

return AceFoodDecayService