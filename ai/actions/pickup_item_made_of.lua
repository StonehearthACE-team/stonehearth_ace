local Entity = _radiant.om.Entity

local PickupItemMadeOf = radiant.class()

PickupItemMadeOf.name = 'pickup item made of'
PickupItemMadeOf.does = 'stonehearth:pickup_item_made_of'
PickupItemMadeOf.args = {
   material = 'string',      -- the material tags we need
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },

   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
PickupItemMadeOf.think_output = {
   item = Entity,            -- what was actually picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
PickupItemMadeOf.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PickupItemMadeOf)
         :execute('stonehearth_ace:material_to_filter_fn_for_pickup', {
            material = ai.ARGS.material,
            owner = ai.ARGS.owner_player_id or ai.ENTITY:get_player_id()
         })
         :execute('stonehearth:pickup_item_type', {
            filter_fn = ai.PREV.filter_fn,
            description = ai.ARGS.material,
            owner_player_id = ai.ARGS.owner_player_id,
            rating_fn = ai.ARGS.rating_fn
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.PREV.path_length,
         })
