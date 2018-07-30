local PetEatFromStorage = radiant.class()

PetEatFromStorage.name = 'pet eat from storage'
PetEatFromStorage.does = 'stonehearth:pet_eat_directly'
PetEatFromStorage.args = {}
PetEatFromStorage.think_output = {
   food_filter_fn = 'function',
}
PetEatFromStorage.priority = 0

local function make_food_filter(food_preferences)
   return stonehearth.ai:filter_from_key('food_filter', tostring(food_preferences),
		function(food_stuff)
			local food = food_stuff
			local container_data = radiant.entities.get_entity_data(food, 'stonehearth:food_container', false)
			if container_data then
				food = container_data.food
			end
			local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

			if not food_data or not food_data.default then
				return false
			end

			if food_preferences ~= '' then
				if not radiant.entities.is_material(food_stuff, food_preferences) then
					return false
				end
			end

			return true
		end)
end

function PetEatFromStorage:start_thinking(ai, entity, args)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')

   ai:set_think_output( { food_filter_fn = make_food_filter(diet_data and diet_data.food_material or '') } )
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFromStorage)
         :execute('stonehearth:get_food_container_from_storage', 
		 {
			food_filter_fn = ai.PREV.food_filter_fn,
			food_rating_fn = function() return 1 end
		 })
         :execute('stonehearth:pet_eat_from_container_adjacent', { container = ai.PREV.container })
