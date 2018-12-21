local PetEatFromStorage = radiant.class()

PetEatFromStorage.name = 'pet eat food container from storage'
PetEatFromStorage.does = 'stonehearth:pet_eat_directly'
PetEatFromStorage.args = {}
PetEatFromStorage.think_output = {
   food_filter_fn = 'function',
}
PetEatFromStorage.priority = 0

local function make_food_container_filter(owner_id, food_filter_fn)
   return function(item)
         if not radiant.entities.is_material(item, 'food_container') then
            return false
         end
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         return food_filter_fn(item)
      end
end

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
   local owner_id = radiant.entities.get_player_id(entity)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
	local food_filter_fn = make_food_filter(diet_data and diet_data.food_material or '') 
   local key = tostring(args.food_filter_fn) .. ':' .. owner_id
   ai:set_think_output( { 
      food_container_filter_fn = stonehearth.ai:filter_from_key('food_container_filter', key, make_food_container_filter(owner_id, food_filter_fn)),
		food_filter_fn = food_filter_fn,
		food_rating_fn = function() return 1 end
	} )
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFromStorage)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
				filter_fn = ai.BACK(2).food_container_filter_fn,
            rating_fn = ai.BACK(2).food_rating_fn,
            description = 'find path to food container',
         })
         :execute('stonehearth:pickup_item_type_from_storage', {
            filter_fn = ai.BACK(3).food_filter_fn,
            rating_fn = ai.BACK(3).food_rating_fn,
            storage = ai.PREV.storage,
            description = 'find path to food container',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
         :execute('stonehearth:drop_carrying_now', {})
         -- this will never execute because the default pet_eat_from_container will get triggered first
			:execute('stonehearth:pet_eat_from_container_adjacent',{ container = ai.BACK(3).item })
