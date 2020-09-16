local Entity = _radiant.om.Entity
local PutRestockableItemIntoBackpack = radiant.class()

PutRestockableItemIntoBackpack.name = 'find and put item into backpack'
PutRestockableItemIntoBackpack.does = 'stonehearth:put_restockable_item_into_backpack'
PutRestockableItemIntoBackpack.args = {
   filter_fn  = 'function',
   filter_key = 'string',
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
PutRestockableItemIntoBackpack.priority = {0, 1}
PutRestockableItemIntoBackpack.think_output = {
   item = Entity,                      -- the item what was put into the backpack
}

function PutRestockableItemIntoBackpack:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:pickup_item_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(PutRestockableItemIntoBackpack)
         :execute('stonehearth:pickup_item_type', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = stonehearth.inventory.rate_item,
            description = ai.ARGS.filter_key,
            owner_player_id = ai.ARGS.owner_player_id,
            ignore_workbenches = false,
         })
         :execute('stonehearth:put_carrying_in_backpack', {
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :set_think_output({
            item = ai.BACK(2).item
         })
