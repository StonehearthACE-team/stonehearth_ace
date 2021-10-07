local Entity = _radiant.om.Entity

local PickupItemIntoBackpack = radiant.class()

PickupItemIntoBackpack.name = 'pick up item into backpack'
PickupItemIntoBackpack.does = 'stonehearth:pickup_item_into_backpack'
PickupItemIntoBackpack.args = {
   item = Entity,
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   is_restocking = {
      type = 'boolean',
      default = false,
   }
}
PickupItemIntoBackpack.priority = 0

function PickupItemIntoBackpack:start_thinking(ai, entity, args)
   local sc = entity:get_component('stonehearth:storage')
   if sc and not sc:is_full() then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupItemIntoBackpack)
   :execute('stonehearth:pickup_item', {
      item = ai.ARGS.item,
      owner_player_id = ai.ARGS.owner_player_id,
      is_restocking = ai.ARGS.is_restocking,
   })
   :execute('stonehearth:put_carrying_in_backpack', { owner_player_id = ai.ARGS.owner_player_id })
