local Entity = _radiant.om.Entity
local GetFoodFromContainer = radiant.class()

GetFoodFromContainer.name = 'get food from container'
GetFoodFromContainer.does = 'stonehearth:get_food'
GetFoodFromContainer.args = {
   food_filter_fn = 'function',
   food_rating_fn = 'function',
}
GetFoodFromContainer.think_output = {
   food_container_filter_fn = 'function',
}
GetFoodFromContainer.priority = {0, 1}

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

function GetFoodFromContainer:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local key = tostring(args.food_filter_fn) .. ':' .. owner_id
   ai:set_think_output({
         food_container_filter_fn = stonehearth.ai:filter_from_key('food_container_filter', key, make_food_container_filter(owner_id, args.food_filter_fn)),
      })
end

function GetFoodFromContainer:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(GetFoodFromContainer)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).food_container_filter_fn,
            rating_fn = ai.ARGS.food_rating_fn,
            description = 'food container filter',
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         --:execute('stonehearth:reserve_entity', { entity = ai.BACK(3).item })
         :execute('stonehearth:get_food_from_container_adjacent', { container = ai.BACK(3).item })

