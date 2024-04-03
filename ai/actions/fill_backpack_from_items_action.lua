local Entity = _radiant.om.Entity

local FillBackpackFromItems = radiant.class()

FillBackpackFromItems.name = 'fill backpack from items'
FillBackpackFromItems.does = 'stonehearth:fill_backpack_from_items'
FillBackpackFromItems.args = {
   candidates = 'table',    -- A sorted table of items to consider, each item being a table with {entity: Entity, score: number}.
   range = {                -- Maximum distance between the character location and the items (for pathfinding optimization)
      type = 'number',
      default = 32,
   },
   storage = Entity,
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   reserve_space = {
      type = 'boolean',
      default = true,
   },
   max_items = {
      type = 'number',
      default = stonehearth.ai.NIL,
   },
   filter_fn = {            -- an optional filter function to limit what gets picked up
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
FillBackpackFromItems.priority = 0

local ai = stonehearth.ai
local action = ai:create_compound_action(FillBackpackFromItems)

-- Should this use a :loop() instead?
for i = 1, stonehearth.constants.backpack.MAX_CAPACITY - 1 do
   action:execute('stonehearth:put_another_restockable_item_into_backpack', {
         range = 32,
         candidates = ai.ARGS.candidates,
         storage = ai.ARGS.storage,
         owner_player_id = ai.ARGS.owner_player_id,
         reserve_space = ai.ARGS.reserve_space,
         max_items = ai.ARGS.max_items,
         filter_fn = ai.ARGS.filter_fn
      })
end

return action
