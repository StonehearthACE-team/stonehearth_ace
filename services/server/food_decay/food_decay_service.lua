-- ACE: overriding in order to change initialize function

-- Service that ticks once per hour to decay food.
local rng = _radiant.math.get_default_rng()

FoodDecayService = class()

local VERSIONS = {
   ZERO = 0,
   TRACK_DECAY_MANUALLY = 1,
   FIX_LOST_ROTTEN_ITEMS = 2,
   KEEP_ENTITY_DATA_REF = 3,
}

function FoodDecayService:get_version()
   return VERSIONS.KEEP_ENTITY_DATA_REF
end

function FoodDecayService:initialize()
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

   -- ACE: just use the post_create_listener instead
   -- this addresses the issue of crafted food/items being immediately placed into storage instead of into the world
   -- local entity_container = radiant._root_entity:add_component('entity_container')
   -- self._entity_container_trace = entity_container:trace_children('FoodDecayService food in world')
   --    :on_added(function(id, entity)
   --          self:_on_entity_added_to_world(entity)
   --       end)

   radiant.events.listen(radiant, 'radiant:entity:post_destroy', function(e)
         local entity_id = e.entity_id
         self:_on_entity_destroyed(entity_id)
      end)

   -- ACE: always use this, not just pre-load for old versions
   self._post_create_listener = radiant.events.listen(radiant, 'radiant:entity:post_create', function(e)
         local entity = e.entity
         self:_on_entity_added_to_world(entity)
      end)

   self._biome_initialized_listener = radiant.events.listen(stonehearth.world_generation, 'stonehearth:world_generation:biome_initialized', function(e)
         self:_update_decay_per_hour()
      end)

   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
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

function FoodDecayService:fixup_post_load()
   if self._sv.version < VERSIONS.TRACK_DECAY_MANUALLY then
      for _, food_decay_data in pairs(self._sv._decaying_food) do
         local decaying_food = food_decay_data.entity
         if decaying_food and decaying_food:is_valid() then
            food_decay_data.decay = radiant.entities.get_attribute(decaying_food, 'decay') or 10
         end
      end

      if self._sv._rotten_food then
         for id, entity in pairs(self._sv._rotten_food) do
            if entity and entity:is_valid() then
               self:_on_entity_added_to_world(entity)
            end
         end
      end

      self._sv._rotten_food = nil
   end

   if self._sv.version < VERSIONS.KEEP_ENTITY_DATA_REF then
      for _, entry in pairs(self._sv._decaying_food) do
         entry.decay_tuning = radiant.entities.get_entity_data(entry.entity, 'stonehearth:food_decay', false)
      end
   end

   self._sv.version = self:get_version()
end

function FoodDecayService:get_raw_food_count()
   return self._sv.food_type_counts[self.food_type_tags[1]] or 0
end

function FoodDecayService:get_prepared_food_count()
   return self._sv.food_type_counts[self.food_type_tags[2]] or 0
end

function FoodDecayService:get_luxury_food_count()
   return self._sv.food_type_counts[self.food_type_tags[3]] or 0
end

function FoodDecayService:_on_decay()
   if not self.enable_decay then
      return
   end

   local decaying_food = self._sv._decaying_food
   local ids = {} -- table can be added to while iterating TODO(yshan) how expensive is this?
   for id, _ in pairs(decaying_food) do
      table.insert(ids, id)
   end

   for _, id in ipairs(ids) do
      self:increment_decay(decaying_food[id])
   end
end

-- ACE: use separate _get_decay_rate function to allow for storage or other factors to change the rate for this entity
function FoodDecayService:increment_decay(food_decay_data)
   local entity = food_decay_data.entity

   local decay_tuning = food_decay_data.decay_tuning
   local initial_decay = food_decay_data.decay
   local decay_rate = self:_get_decay_rate(entity, decay_tuning, self._decay_per_hour)
   if decay_rate == 0 then
      return
   end

   local decay = initial_decay - decay_rate
   food_decay_data.decay = decay
   if decay <= 0 then
      self:_convert_to_rotten_form(entity, decay_tuning.rotten_entity_alias)
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

function FoodDecayService:_update_decay_per_hour()
   local biome = stonehearth.world_generation:get_biome()
   if biome then
      -- Calculate decay per hour based on biome decay multiplier, if specified
      local biome_decay_multiplier = biome.decay_multiplier or 1
      self._decay_per_hour = biome_decay_multiplier * stonehearth.constants.food_decay.DEFAULT_DECAY_PER_HOUR
   end
end

function FoodDecayService:_convert_to_rotten_form(entity, rotten_alias)
   local inventory = nil
   local storage_component = nil
   local location = nil
   local rotten_entity
   if rotten_alias then
      -- Replace Food with a rotten form
      local player_id = entity:get_player_id()
      -- ACE: only try to create the rotten food entity if there's an actual player id
      if player_id and player_id ~= '' then
         inventory = stonehearth.inventory:get_inventory(player_id)
         location = radiant.entities.get_world_grid_location(entity)
         rotten_entity = radiant.entities.create_entity(rotten_alias, { owner = player_id })
         if not location then
            -- if no location, is it in storage?
            local storage = inventory and inventory:container_for(entity)
            if storage then
               storage_component = storage:get_component('stonehearth:storage')
            end
         end
      end
   end
   if inventory then
      inventory:remove_item(entity:get_id())
   end
   -- Food is rotten beyond recognition. Destroy it.
   radiant.entities.destroy_entity(entity)
   if rotten_entity then
      if location then
         radiant.terrain.place_entity(rotten_entity, location)
      elseif not storage_component or not storage_component:add_item(rotten_entity, true) then
         if inventory then
            inventory:add_item(rotten_entity)
         end
      end
      self:_on_entity_added_to_world(rotten_entity)
   end
end

function FoodDecayService:_get_food_type(entity)
   for _, food_type in ipairs(self.food_type_tags) do
      if radiant.entities.is_material(entity, food_type) then
         return food_type
      end
   end
   return 'unknown'
end

function FoodDecayService:_get_decay_rate(entity, tuning, rate)
   if tuning.storage_modifiers or tuning.any_storage_modifier or tuning.ground_modifier then
      local player_id = entity:get_player_id()
      if player_id and player_id ~= '' then
         local inventory = stonehearth.inventory:get_inventory(player_id)
         local storage = nil
         if inventory then
            storage = inventory:container_for(entity)
         end
         if storage then
            local best_rate = 1
            -- check if the storage matches any materials in the decay modifiers
            if tuning.any_storage_modifier then
               best_rate = best_rate * tuning.any_storage_modifier
            end
            if tuning.storage_modifiers then
               for material, modified_rate in pairs(tuning.storage_modifiers) do
                  if radiant.entities.is_material(storage, material) then
                     best_rate = modified_rate
                  end
               end
            end

            rate = rate * best_rate
         else
            if tuning.ground_modifier then
               rate = rate * tuning.ground_modifier
            end
         end
      end
   end

   return rate
end

function FoodDecayService:_on_entity_added_to_world(entity)
   local id = entity:get_id()
   if self._sv._decaying_food[id] then
      return
   end

   local decay_tuning = radiant.entities.get_entity_data(entity, 'stonehearth:food_decay', false) -- do not throw error
   if decay_tuning then

      local food_type = self:_get_food_type(entity)
      local initial_decay = 10
      if decay_tuning.initial_decay then
         initial_decay = rng:get_int(decay_tuning.initial_decay.min, decay_tuning.initial_decay.max)
      end
      self._sv._decaying_food[id] = { entity = entity, food_type = food_type, decay = initial_decay, decay_tuning = decay_tuning }

      local count = self._sv.food_type_counts[food_type] or 0
      count = count + 1
      self._sv.food_type_counts[food_type] = count
   end
end

function FoodDecayService:_on_entity_destroyed(entity_id)
   local decay_data = self._sv._decaying_food[entity_id]
   if decay_data then -- If what's being destroyed is a food
      local food_type = decay_data.food_type
      local count = self._sv.food_type_counts[food_type]
      if count then
         count = count - 1
         self._sv.food_type_counts[food_type] = count
      end
      self._sv._decaying_food[entity_id] = nil
   end
end

function FoodDecayService:debug_decay_to_next_stage(entity)
   local food_decay_data = self._sv._decaying_food[entity:get_id()]
   if not food_decay_data then
      return false
   end

   local decay_tuning = radiant.entities.get_entity_data(entity, 'stonehearth:food_decay')
   local largest_trigger_value = 0
   local decay = food_decay_data.decay
   for _, decay_stage in pairs(decay_tuning.decay_stages) do
      -- Find the next decay stage
      if decay > decay_stage.trigger_decay_value and decay_stage.trigger_decay_value > largest_trigger_value then
         largest_trigger_value = decay_stage.trigger_decay_value
      end
   end

   food_decay_data.decay = largest_trigger_value
   return self:increment_decay(food_decay_data)
end

return FoodDecayService
