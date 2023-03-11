local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local PetEatFromPetFoodBowl = radiant.class()

PetEatFromPetFoodBowl.name = 'pet eat from pet food bowl'
PetEatFromPetFoodBowl.does = 'stonehearth:pet_eat_directly'
PetEatFromPetFoodBowl.args = {}
PetEatFromPetFoodBowl.think_output = {
   owner_player_id = 'string',
   food_container_filter_fn = 'function',
}
PetEatFromPetFoodBowl.priority = 1

local log = radiant.log.create_logger('pet_eat_from_pet_food_bowl')

local function make_pet_food_bowl_filter(owner_id, food_preferences, inventory)
   return stonehearth.ai:filter_from_key('pet_food_bowl_filter', tostring(food_preferences) .. ":" .. owner_id,
      function(food_container)
         -- first check container type to see if it's a pet food bowl
         if inventory then
            local storage = inventory:container_for(food_container)
            if not storage or not radiant.entities.is_material(storage, 'pet_food_bowl') then
               return false
            end
         else
            return false
         end

         local catalog_data = stonehearth.catalog:get_catalog_data(food_container:get_uri())
         if not catalog_data or not catalog_data.is_pet_food then
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

function PetEatFromPetFoodBowl:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
   local inventory = stonehearth.inventory:get_inventory(owner_id)
   if inventory then
	   local food_container_filter_fn = make_pet_food_bowl_filter(owner_id, diet_data and diet_data.food_material or '', inventory) 
      ai:set_think_output({
         owner_player_id = owner_id,
         food_container_filter_fn = food_container_filter_fn,
      })
   end
end

function PetEatFromPetFoodBowl:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_reachable_storage_containing_best_entity_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFromPetFoodBowl)
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
				filter_fn = ai.BACK(1).food_container_filter_fn,
            description = 'find path to food container',
         })
         :execute('stonehearth:find_entity_type_in_storage', {
				filter_fn = ai.BACK(2).food_container_filter_fn,
            storage = ai.BACK(1).storage,
            owner_player_id = ai.BACK(2).owner_player_id,
         })
         :execute('stonehearth:goto_entity_in_storage', {
            entity = ai.PREV.item,
         })
			:execute('stonehearth:pet_eat_from_container_adjacent', {
            container = ai.BACK(2).item,
            storage = ai.BACK(3).storage,
         })
