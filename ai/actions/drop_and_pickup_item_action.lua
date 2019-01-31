local Entity = _radiant.om.Entity
local DropAndPickupItem = class()

DropAndPickupItem.name = 'drop and pickup item'
DropAndPickupItem.does = 'stonehearth_ace:drop_and_pickup_item'
DropAndPickupItem.args = {
   found_item = Entity,
   found_rating = {
      type = 'number',
      default = 1
   },
   carrying_rating = {
      type = 'number',
      default = stonehearth.ai.NIL
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
DropAndPickupItem.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
DropAndPickupItem.priority = {0, 1}

local log = radiant.log.create_logger('drop_and_pickup')

function DropAndPickupItem:start_thinking(ai, entity, args)
   self._found_rating = args.found_rating
   local carrying = ai.CURRENT.carrying
   local rating = args.carrying_rating
   if carrying and (not rating or rating < args.found_rating) then
      ai:set_think_output()
      --log:debug('%s all set to drop %s to pickup %s', entity, carrying, args.found_item)
   end
end

function DropAndPickupItem:compose_utility(entity, self_utility, child_utilities, current_activity)
   return self._found_rating * 0.8
        + child_utilities:get('stonehearth:follow_path') * 0.2
end

local ai = stonehearth.ai
return ai:create_compound_action(DropAndPickupItem)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.ARGS.found_item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).path:get_destination(),
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth:pickup_item_adjacent', {
            item = ai.PREV.entity,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.BACK(4).path:get_path_length()
         })
