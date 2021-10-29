
local AcePickupItemAdjacent = radiant.class()

PickupItemAdjacent.name = 'pickup an item (adjacent)'
PickupItemAdjacent.does = 'stonehearth:pickup_item_adjacent'
PickupItemAdjacent.args = {
   item = Entity,
   relative_orientation = {
      type = 'number',
      default = stonehearth.ai.NIL,
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
PickupItemAdjacent.priority = 0.0

local log = radiant.log.create_logger('actions.pickup_item')

function PickupItemAdjacent:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      ai:set_debug_progress('dead: already carrying')
   else
      ai.CURRENT.carrying = args.item
      ai:set_think_output()
   end
end

function PickupItemAdjacent:run(ai, entity, args)
   local item = args.item
   radiant.check.is_entity(item)

   -- delibrately break up the prepare vs pickup steps to make sure
   -- we're not carrying anything before playing the animation (and
   -- if we *are* carrying the right thing already, skip the animation
   -- entirely) - tony
   if stonehearth.ai:prepare_to_pickup_item(ai, entity, item, args.owner_player_id) then
      return
   end
   assert(not radiant.entities.get_carrying(entity))

   if not radiant.entities.is_adjacent_to(entity, item) then
      ai:abort(string.format('%s is not adjacent to %s', tostring(entity), tostring(item)))
      return
   end

   log:info("%s picking up %s", entity, item)
   local item_location = radiant.entities.get_world_grid_location(item)
   radiant.entities.turn_to_face(entity, item, true)
   stonehearth.ai:pickup_item(ai, entity, item, args.relative_orientation, args.owner_player_id)
   ai:execute('stonehearth:run_pickup_effect', { location = item_location })
end

return PickupItemAdjacent
