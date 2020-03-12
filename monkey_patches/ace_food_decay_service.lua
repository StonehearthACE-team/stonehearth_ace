-- Service that ticks once per hour to decay food.
local FoodDecayService = require 'stonehearth.services.server.food_decay.food_decay_service'
local AceFoodDecayService = class()

function AceFoodDecayService:_get_decay_rate(entity, tuning, rate)
   if tuning.storage_modifiers or tuning.any_storage_modifier then
      local player_id = entity:get_player_id()
      if player_id then
         inventory = stonehearth.inventory:get_inventory(player_id)
         local storage = inventory:container_for(entity)
         if storage then
            local best_rate = 1
            -- check if the storage matches any materials in the decay modifiers
            for material, modified_rate in pairs(tuning.storage_modifiers) do
               if modified_rate < best_rate and radiant.entities.is_material(storage, material) then
                  best_rate = modified_rate
               end
            end
            if tuning.any_storage_modifier then
               best_rate = best_rate * tuning.any_storage_modifier
            end

            rate = rate * best_rate
         end
      end
   end

   return rate
end

function AceFoodDecayService:increment_decay(food_decay_data)
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

return AceFoodDecayService
