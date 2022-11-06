local Entity = _radiant.om.Entity
local GetDrinkOnGround = class()

GetDrinkOnGround.name = 'get drink on the ground'
GetDrinkOnGround.does = 'stonehearth_ace:get_drink'
GetDrinkOnGround.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = {           -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
GetDrinkOnGround.think_output = {
   drink_filter_fn = 'function',
}
GetDrinkOnGround.priority = {0, 1}

local function make_filter_fn(owner_id, drink_filter_fn)
   return function(item)
         if owner_id ~= nil and owner_id ~= radiant.entities.get_player_id(item) then
            return false
         end
         return radiant.entities.is_material(item, 'drink') and drink_filter_fn(item)
      end
end

function GetDrinkOnGround:start_thinking(ai, entity, args)
   local owner_id = radiant.entities.get_player_id(entity)
   local key = tostring(args.drink_filter_fn) .. ':' .. owner_id
   ai:set_think_output({
         drink_filter_fn = stonehearth.ai:filter_from_key('find_drink_on_ground', key, make_filter_fn(owner_id, args.drink_filter_fn))
      })
end

function GetDrinkOnGround:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkOnGround)
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).drink_filter_fn,
            rating_fn = ai.ARGS.drink_rating_fn,
            description = 'drink on ground filter',
         })
         :execute('stonehearth:pickup_item', {
            item = ai.PREV.item
         })