local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local PetEatFoodContainerFromStorage = radiant.class()

PetEatFoodContainerFromStorage.name = 'pet eat food container from storage'
PetEatFoodContainerFromStorage.does = 'stonehearth:pet_eat_directly'
PetEatFoodContainerFromStorage.args = {}
PetEatFoodContainerFromStorage.think_output = {
   food_container_filter_fn = 'function',
}
PetEatFoodContainerFromStorage.priority = 0

local log = radiant.log.create_logger('pet_eat_food_container_from_storage')

local function make_food_container_filter(owner_id, food_preferences)
   return stonehearth.ai:filter_from_key('food_container_filter', tostring(food_preferences) .. ":" .. owner_id,
      function(food_container)
         if not EatingLib.is_edible(food_container) then
            return false
         end

         if owner_id ~= '' and radiant.entities.get_player_id(food_container) ~= owner_id then
            return false
         end

			if food_preferences ~= '' then
				if not radiant.entities.is_material(food_container, food_preferences) then
					return false
				end
			end

			return true
		end)
end

local function pet_food_rating_fn(item)
   local catalog_data = stonehearth.catalog:get_catalog_data(item:get_uri())
   return catalog_data and catalog_data.food_attributes and catalog_data.food_attributes.is_pet_food and 1 or 0
end

function PetEatFoodContainerFromStorage:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
	local food_container_filter_fn = make_food_container_filter(owner_id, diet_data and diet_data.food_material or '') 
   ai:set_think_output( { 
      food_container_filter_fn = food_container_filter_fn,
      food_rating_fn = pet_food_rating_fn,
      -- function(item)
      --    if radiant.entities.is_material(item, 'pet_food') then
      --       return 1
      --    else
      --       return 0
      --    end
      -- end
	})
end

function PetEatFoodContainerFromStorage:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_reachable_storage_containing_best_entity_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFoodContainerFromStorage)
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
				filter_fn = ai.BACK(1).food_container_filter_fn,
            rating_fn = ai.BACK(1).food_rating_fn,
            description = 'find path to food container',
         })
         :execute('stonehearth_ace:pet_pull_item_type_from_storage', {
            filter_fn = ai.BACK(2).food_container_filter_fn,
            rating_fn = ai.BACK(2).food_rating_fn,
            storage = ai.PREV.storage,
            description = 'find path to food container',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
			:execute('stonehearth:pet_eat_from_container_adjacent', { container = ai.BACK(2).item })
