local PetEatFoodFromStorage = radiant.class()

PetEatFoodFromStorage.name = 'pet eat food from storage'
PetEatFoodFromStorage.does = 'stonehearth:pet_eat_directly'
PetEatFoodFromStorage.args = {}
PetEatFoodFromStorage.think_output = {
   food_filter_fn = 'function',
}
PetEatFoodFromStorage.priority = 0

local function make_food_filter(owner_id, food_preferences)
   return stonehearth.ai:filter_from_key('food_filter', tostring(food_preferences) .. ":" .. owner_id,
		function(food)
         if not radiant.entities.is_material(food, 'food') and not radiant.entities.is_material(food, 'pet_food') then
            return false
         end
         if owner_id ~= '' and radiant.entities.get_player_id(food) ~= owner_id then
            return false
         end
			local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

			if not food_data or not food_data.default then
				return false
			end

			if food_preferences ~= '' then
				if not radiant.entities.is_material(food, food_preferences) then
					return false
				end
			end

			return true
		end)
end

function PetEatFoodFromStorage:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
	local food_filter_fn = make_food_filter(owner_id, diet_data and diet_data.food_material or '') 
   ai:set_think_output( { 
		food_filter_fn = food_filter_fn,
      food_rating_fn = function(item)
         if radiant.entities.is_material(item, 'pet_food') then
            return 1
         else
            return 0
         end
      end
	} )
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFoodFromStorage)
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
				filter_fn = ai.BACK(1).food_filter_fn,
            rating_fn = ai.BACK(1).food_rating_fn,
            description = 'find path to food',
         })
         :execute('stonehearth_ace:pet_pull_item_type_from_storage', {
            filter_fn = ai.BACK(2).food_filter_fn,
            rating_fn = ai.BACK(2).food_rating_fn,
            storage = ai.PREV.storage,
            description = 'find path to food',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
			:execute('stonehearth:eat_item', { food = ai.BACK(2).item })
