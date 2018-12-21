local Entity = _radiant.om.Entity
local PetPullItemTypeFromStorage = radiant.class()

PetPullItemTypeFromStorage.name = 'pet pull item type from storage'
PetPullItemTypeFromStorage.does = 'stonehearth_ace:pet_pull_item_type_from_storage'
PetPullItemTypeFromStorage.args = {
   storage = Entity,
   filter_fn = 'function',
   rating_fn = {           -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
PetPullItemTypeFromStorage.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
PetPullItemTypeFromStorage.priority = {0, 1}

function PetPullItemTypeFromStorage:start(ai, entity, args)
   print('ran')
   self._storage_location_trace = radiant.entities.trace_location(args.storage, 'storage location trace')
      :on_changed(function()
            ai:abort('storage container moved')
         end)
end

function PetPullItemTypeFromStorage:stop(ai, entity, args)
   if self._storage_location_trace then
      self._storage_location_trace:destroy()
      self._storage_location_trace = nil
   end
end

function PetPullItemTypeFromStorage:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_entity_type_in_storage') * 0.8
        + child_utilities:get('stonehearth:goto_entity_in_storage') * 0.2
end

local ai = stonehearth.ai
return ai:create_compound_action(PetPullItemTypeFromStorage)
         :execute('stonehearth:find_entity_type_in_storage', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = ai.ARGS.rating_fn,
            storage = ai.ARGS.storage,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth:goto_entity_in_storage', {
            entity = ai.PREV.item,
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).item,
            reserve_from_self = true,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth_ace:pet_pull_item_from_storage_adjacent', {
            item = ai.BACK(3).item,
            storage = ai.ARGS.storage,
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.BACK(3).path_length,
         })
