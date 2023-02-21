local GetFoodFromContainerFromStorage = radiant.class()

GetFoodFromContainerFromStorage.name = 'get food from container in storage'
GetFoodFromContainerFromStorage.does = 'stonehearth:get_food'
GetFoodFromContainerFromStorage.args = {
   food_filter_fn = 'function',
   food_rating_fn = 'function',
}
GetFoodFromContainerFromStorage.think_output = {
   food_container_filter_fn = 'function',
}
GetFoodFromContainerFromStorage.priority = {0, 1}

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

function GetFoodFromContainerFromStorage:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local key = tostring(args.food_filter_fn) .. ':' .. owner_id
   ai:set_think_output({
         food_container_filter_fn = stonehearth.ai:filter_from_key('food_container_filter', key, make_food_container_filter(owner_id, args.food_filter_fn)),
      })
end

function GetFoodFromContainerFromStorage:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_reachable_storage_containing_best_entity_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(GetFoodFromContainerFromStorage)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
            filter_fn = ai.BACK(2).food_container_filter_fn,
            rating_fn = ai.ARGS.food_rating_fn,
            description = 'find path to food container',
         })
         :execute('stonehearth:find_entity_type_in_storage', {
            filter_fn = ai.ARGS.food_filter_fn,
            rating_fn = ai.ARGS.food_rating_fn,
            storage = ai.PREV.storage,
            description = 'find path to food container',
         })
         :execute('stonehearth:goto_entity_in_storage', {
            entity = ai.PREV.item,
         })
         :execute('stonehearth_ace:get_food_from_container', {
            container = ai.BACK(2).item,
            storage = ai.BACK(3).storage,
         })
