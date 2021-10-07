local Entity = _radiant.om.Entity

local FillStorageFromBackpack = radiant.class()

FillStorageFromBackpack.name = 'fill storage from backpack'
FillStorageFromBackpack.does = 'stonehearth:fill_storage_from_backpack'
FillStorageFromBackpack.args = {
   filter_fn = 'function',            -- which items to take from the backpack
   storage = Entity,                  -- where to put the items
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   ignore_missing = {
      type = 'boolean',
      default = false,
   },
}
FillStorageFromBackpack.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(FillStorageFromBackpack)
      :loop({
         name = 'empty backpack',
         break_timeout = 2000,
         break_condition = function(ai, entity, args)
            return not next(ai.CURRENT.storage.items)
         end
      })
         :execute('stonehearth:pickup_item_type_from_backpack', {
            filter_fn = ai.UP.ARGS.filter_fn,
            description = 'items to restock',
            owner_player_id = ai.UP.ARGS.owner_player_id,
            ignore_missing = ai.UP.ARGS.ignore_missing,
         })
         :execute('stonehearth:drop_carrying_in_storage', {
            storage = ai.UP.ARGS.storage,
            ignore_missing = ai.UP.ARGS.ignore_missing,
         })
      :end_loop()
