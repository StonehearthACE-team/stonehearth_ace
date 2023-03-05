local Entity = _radiant.om.Entity
local DrinkingLib = require 'stonehearth_ace.ai.lib.drinking_lib'
local GetDrinkFromContainer = class()

GetDrinkFromContainer.name = 'get drink from container'
GetDrinkFromContainer.does = 'stonehearth_ace:get_drink'
GetDrinkFromContainer.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = {           -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
GetDrinkFromContainer.think_output = {
   drink_container_filter_fn = 'function'
}
GetDrinkFromContainer.priority = {0, 1}

local log = radiant.log.create_logger('get_drink_from_container')

local function make_drink_container_filter(owner_id, drink_filter_fn)
   return function(item)
         if not DrinkingLib.is_drinkable(item) then
            return false
         end
         if owner_id ~= '' then
            local player_id = radiant.entities.get_player_id(item)
            if player_id ~= '' and player_id ~= owner_id then
               return false
            end
         end
         return drink_filter_fn(item)
      end
end

function GetDrinkFromContainer:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local key = tostring(args.drink_filter_fn) .. ':' .. owner_id
   ai:set_think_output({
      drink_container_filter_fn = stonehearth.ai:filter_from_key('drink_container_filter', key, make_drink_container_filter(owner_id, args.drink_filter_fn))
   })
end

function GetDrinkFromContainer:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkFromContainer)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).drink_container_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            description = 'drink container filter'
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth_ace:get_drink_from_container', { container = ai.BACK(3).item })
