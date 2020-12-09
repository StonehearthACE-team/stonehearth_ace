local Entity = _radiant.om.Entity
local GOLD_URI = 'stonehearth:loot:gold'

local PickupGoldCoinsAdjacent = radiant.class()

PickupGoldCoinsAdjacent.name = 'pickup some gold coins (adjacent)'
PickupGoldCoinsAdjacent.does = 'stonehearth_ace:pickup_gold_coins_adjacent'
PickupGoldCoinsAdjacent.args = {
   source = Entity,
   amount = 'number',
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
PickupGoldCoinsAdjacent.priority = 0.0

local log = radiant.log.create_logger('actions.pickup_item')

function PickupGoldCoinsAdjacent:start_thinking(ai, entity, args)
   self._inventory = stonehearth.inventory:get_inventory(args.owner_player_id)
   self._amount = args.amount

   if self:_can_pickup_gold() then
      ai:set_think_output({})
   end
end

function PickupGoldCoinsAdjacent:_can_pickup_gold()
   if self._inventory and self._inventory:get_gold_count() >= self._amount then
      return true
   end
end

function PickupGoldCoinsAdjacent:run(ai, entity, args)
   if not self:_can_pickup_gold() then
      ai:abort('not enough gold in inventory anymore!')
   end

   local location = radiant.entities.get_world_grid_location(args.source)
   radiant.entities.turn_to_face(entity, args.source, true)

   -- if the source of the gold is a gold entity, try to just remove stacks from that
   -- if it's a storage container, remove first from that storage container
   -- remove any remaining amount of gold requested from the inventory
   self._inventory:subtract_gold(self._amount, args.source)

   local gold = radiant.entities.create_entity(GOLD_URI, {owner = args.owner_player_id or entity})
   gold:add_component('stonehearth:stacks'):set_stacks(self._amount)

   -- delibrately break up the prepare vs pickup steps to make sure
   -- we're not carrying anything before playing the animation (and
   -- if we *are* carrying the right thing already, skip the animation
   -- entirely) - tony
   if stonehearth.ai:prepare_to_pickup_item(ai, entity, gold, args.owner_player_id) then
      return
   end

   stonehearth.ai:pickup_item(ai, entity, gold, args.relative_orientation, args.owner_player_id)
   ai:execute('stonehearth:run_pickup_effect', { location = location })
end

return PickupGoldCoinsAdjacent
