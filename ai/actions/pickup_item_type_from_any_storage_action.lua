local Entity = _radiant.om.Entity
local PickupItemTypeFromAnyStorage = radiant.class()

PickupItemTypeFromAnyStorage.name = 'pickup item type from any storage'
PickupItemTypeFromAnyStorage.does = 'stonehearth:pickup_item_type'
PickupItemTypeFromAnyStorage.args = {
   filter_fn = 'function',
   rating_fn = {
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',
   from_backpack = {
      type = 'boolean',
      default = true,
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   ignore_consumers = {
      type = 'boolean',
      default = true,
   },
}
PickupItemTypeFromAnyStorage.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
PickupItemTypeFromAnyStorage.priority = {0, 1}

local log = radiant.log.create_logger('pickup_item_type_from_any_storage')

function PickupItemTypeFromAnyStorage:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      log:spam('carrying is %s.  bailing.', tostring(ai.CURRENT.carrying))
      return
   end
   ai:set_think_output({
         description = 'pickup ' .. args.description .. ' (any storage)'
      })
end

function PickupItemTypeFromAnyStorage:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:pickup_item_type_from_storage')
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupItemTypeFromAnyStorage)
         :execute('stonehearth:find_reachable_storage_containing_best_entity_type', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = ai.ARGS.rating_fn,
            description = ai.PREV.description,
            owner_player_id = ai.ARGS.owner_player_id,
            ignore_consumers = ai.ARGS.ignore_consumers,
         })
         :execute('stonehearth:pickup_item_type_from_storage', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = ai.ARGS.rating_fn,
            storage = ai.PREV.storage,
            description = ai.ARGS.description,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.PREV.path_length,
         })
