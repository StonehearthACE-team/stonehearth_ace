local Entity = _radiant.om.Entity
local DropAndPickupItemType = class()

DropAndPickupItemType.name = 'pickup item type'
DropAndPickupItemType.does = 'stonehearth_ace:drop_and_pickup_item_type'
DropAndPickupItemType.args = {
   filter_fn = 'function',
   rating_fn = {
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
DropAndPickupItemType.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
   carrying_rating = {
      type = 'number',
      default = 0
   }
}
DropAndPickupItemType.priority = {0, 1}

local log = radiant.log.create_logger('drop_and_pickup_type')

function DropAndPickupItemType:start_thinking(ai, entity, args)
   local carrying = ai.CURRENT.carrying
   local rating = nil

   if carrying then
      -- evaluate what we're carrying and see if it matches our filter and rating
      if args.filter_fn(carrying) then
         rating = (args.rating_fn and args.rating_fn(carrying)) or 1
      end
   end

   ai:set_think_output({
      description = 'considering picking up ' .. args.description,
      carrying_rating = rating or stonehearth.ai.NIL
   })
end

function DropAndPickupItemType:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth_ace:drop_and_pickup_item')
end

local ai = stonehearth.ai
return ai:create_compound_action(DropAndPickupItemType)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = ai.ARGS.rating_fn,
            description = ai.PREV.description,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth_ace:drop_and_pickup_item', {
            found_item = ai.PREV.item,
            found_rating = ai.PREV.rating,
            carrying_rating = ai.BACK(2).carrying_rating,
            owner_player_id = ai.ARGS.owner_player_id
         })
