local GetDrinkFromContainerFromStorage = class()

GetDrinkFromContainerFromStorage.name = 'get drink from container in storage'
GetDrinkFromContainerFromStorage.does = 'stonehearth_ace:get_drink'
GetDrinkFromContainerFromStorage.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = {           -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
GetDrinkFromContainerFromStorage.think_output = {
   drink_container_filter_fn = 'function',
}
GetDrinkFromContainerFromStorage.priority = {0, 1}

local function make_drink_container_filter(owner_id, drink_filter_fn)
   return function(item)
         if not radiant.entities.is_material(item, 'drink_container') then
            return false
         end
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         return drink_filter_fn(item)
      end
end

function GetDrinkFromContainerFromStorage:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local key = tostring(args.drink_filter_fn) .. ':' .. owner_id
   ai:set_think_output({
         owner_player_id = owner_id,
         drink_container_filter_fn = stonehearth.ai:filter_from_key('drink_container_storage_filter', key, make_drink_container_filter(owner_id, args.drink_filter_fn)),
      })
end

function GetDrinkFromContainerFromStorage:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_reachable_storage_containing_best_entity_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkFromContainerFromStorage)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
            filter_fn = ai.BACK(2).drink_container_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            description = 'find path to drink container',
         })
         :execute('stonehearth:find_entity_type_in_storage', {
            filter_fn = ai.ARGS.drink_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            storage = ai.PREV.storage,
            owner_player_id = ai.BACK(3).owner_player_id,
            description = 'find path to drink container',
         })
         :execute('stonehearth:goto_entity_in_storage', {
            entity = ai.PREV.item,
         })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(2).item })
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth_ace:get_drink_from_container_adjacent', { container = ai.BACK(4).item })
