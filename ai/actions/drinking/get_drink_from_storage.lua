local GetDrinkFromContainerFromStorage = radiant.class()

GetDrinkFromContainerFromStorage.name = 'get drink from storage'
GetDrinkFromContainerFromStorage.does = 'stonehearth_ace:get_drink'
GetDrinkFromContainerFromStorage.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = 'function',
}
GetDrinkFromContainerFromStorage.think_output = {
   drink_container_filter_fn = 'function',
}
GetDrinkFromContainerFromStorage.priority = 0

local function make_drink_container_filter(owner_id, drink_filter_fn)
   return function(item)
         if not radiant.entities.is_material(item, 'drink') then
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
         drink_container_filter_fn = stonehearth.ai:filter_from_key('drink_storage_filter', key, make_drink_container_filter(owner_id, args.drink_filter_fn)),
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkFromContainerFromStorage)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
            filter_fn = ai.BACK(2).drink_container_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            description = 'find path to drink container',
         })
         :execute('stonehearth:pickup_item_type_from_storage', {
            filter_fn = ai.ARGS.drink_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            storage = ai.PREV.storage,
            description = 'find path to drink container',
         })
