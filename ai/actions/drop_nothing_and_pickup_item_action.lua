local Entity = _radiant.om.Entity
local DropNothingAndPickupItem = class()

DropNothingAndPickupItem.name = 'drop and pickup item'
DropNothingAndPickupItem.does = 'stonehearth_ace:drop_and_pickup_item'
DropNothingAndPickupItem.args = {
   found_item = Entity,
   found_rating = {
      type = 'number',
      default = 1
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
DropNothingAndPickupItem.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
DropNothingAndPickupItem.priority = {0, 1}

local log = radiant.log.create_logger('drop_nothing_and_pickup')

function DropNothingAndPickupItem:start_thinking(ai, entity, args)
   self._found_rating = args.found_rating
   local carrying = ai.CURRENT.carrying
   if not carrying then
      ai:set_think_output()
      --log:debug('%s isn\'t carrying anything, ready to pickup %s', entity, args.found_item)
   end
end

function DropNothingAndPickupItem:compose_utility(entity, self_utility, child_utilities, current_activity)
   return self._found_rating * 0.8
        + child_utilities:get('stonehearth:follow_path') * 0.2
end

local ai = stonehearth.ai
return ai:create_compound_action(DropNothingAndPickupItem)
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
